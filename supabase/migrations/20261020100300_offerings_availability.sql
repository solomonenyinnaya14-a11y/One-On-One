-- One On One migration 04: paid-conversation offerings and availability.
--
-- An offering is what a provider sells: a text or voice conversation of a fixed
-- length at a fixed price. Prices are integers in kobo (NGN minor units), never
-- floats. A booking copies these values when it is created, so later edits never
-- change what a customer already bought.
--
-- Free allowance and subscriptions
--   * A provider's FIRST offering is their free allowance (is_free_allowance).
--   * Any further offering needs an active subscription, checked in the database
--     by create_offering(); clients cannot insert offerings directly.
--   * When a subscription is not active, subscription-dependent offerings stay in
--     the database untouched but stop accepting NEW bookings and disappear from
--     public listings. The free-allowance offering keeps working.

set search_path = public, extensions;

create table public.offerings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  topic_id uuid references public.topics (id) on delete restrict,
  kind text not null,
  title text not null,
  description text,
  duration_minutes integer not null,
  price_minor bigint not null,
  currency text not null default 'NGN',
  is_active boolean not null default true,
  is_free_allowance boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint offerings_kind_valid check (kind in ('text', 'voice')),
  constraint offerings_title_length check (char_length(btrim(title)) between 1 and 80),
  constraint offerings_description_length check (description is null or char_length(description) <= 500),
  constraint offerings_duration_valid check (duration_minutes between 10 and 120 and duration_minutes % 5 = 0),
  -- Sanity bounds only (NGN 1 to NGN 1,000,000). Real limits are a product decision.
  constraint offerings_price_valid check (price_minor between 100 and 100000000),
  constraint offerings_currency_valid check (currency = 'NGN')
);

create index offerings_provider_id_idx on public.offerings (provider_id);
create index offerings_topic_id_idx on public.offerings (topic_id);
-- At most one free-allowance offering per provider.
create unique index offerings_one_free_allowance_idx
  on public.offerings (provider_id) where is_free_allowance;

create trigger offerings_set_updated_at
  before update on public.offerings
  for each row execute function private.set_updated_at();

-- Offerings are never deleted: they may be referenced by bookings, and a lapsed
-- subscription must not destroy a provider's configuration.
create trigger offerings_forbid_delete
  before delete on public.offerings
  for each row execute function private.forbid_delete();

-- Can this offering take a NEW booking right now? Single source of truth, used by
-- the public listing policy, create_booking() and the status view.
create function private.offering_accepts_bookings(p_offering uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.offerings o
    where o.id = p_offering
      and o.is_active
      and private.is_public_provider(o.provider_id)
      and (o.is_free_allowance or private.has_active_subscription(o.provider_id))
  );
$$;

alter table public.offerings enable row level security;
revoke all on public.offerings from anon, authenticated;
grant select on public.offerings to anon, authenticated;
-- No insert or delete grants: offerings are created by create_offering() only.
-- is_free_allowance, provider_id, kind and currency can never be edited.
grant update (title, description, topic_id, duration_minutes, price_minor, is_active)
  on public.offerings to authenticated;

-- Public listings show only what can actually be booked.
create policy offerings_select_public on public.offerings
  for select to anon, authenticated
  using (private.offering_accepts_bookings(id));

create policy offerings_select_own on public.offerings
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy offerings_update_own on public.offerings
  for update to authenticated
  using (provider_id = (select auth.uid()))
  with check (provider_id = (select auth.uid()));

-- Same rows, plus a plain "can this be booked now?" flag. Runs with the caller's
-- permissions, so visitors still only see bookable offerings and providers see
-- all of their own (with accepts_bookings = false for lapsed ones).
create view public.offerings_with_status
  with (security_invoker = true) as
  select o.id, o.provider_id, o.topic_id, o.kind, o.title, o.description,
         o.duration_minutes, o.price_minor, o.currency, o.is_active,
         not o.is_free_allowance as requires_subscription,
         private.offering_accepts_bookings(o.id) as accepts_bookings,
         o.created_at, o.updated_at
    from public.offerings o;

revoke all on public.offerings_with_status from anon, authenticated;
grant select on public.offerings_with_status to anon, authenticated;

-- The only way to create an offering.
create function public.create_offering(
  p_kind text,
  p_title text,
  p_description text,
  p_duration_minutes integer,
  p_price_minor bigint,
  p_topic_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_has_free boolean;
  v_count integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Serialise concurrent creations for the same provider.
  perform 1 from public.provider_profiles pp
   where pp.user_id = v_uid and pp.status <> 'suspended'
   for update;
  if not found then
    raise exception 'provider_profile_required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;

  select count(*), coalesce(bool_or(o.is_free_allowance), false)
    into v_count, v_has_free
    from public.offerings o
   where o.provider_id = v_uid;

  if v_count >= 20 then
    raise exception 'too_many_offerings' using errcode = '54000';
  end if;

  -- The first offering is free. Every further one needs an active subscription.
  if v_has_free and not private.has_active_subscription(v_uid) then
    raise exception 'subscription_required' using errcode = '42501';
  end if;

  begin
    insert into public.offerings
      (provider_id, topic_id, kind, title, description, duration_minutes, price_minor, is_free_allowance)
    values
      (v_uid, p_topic_id, p_kind, p_title, nullif(btrim(p_description), ''), p_duration_minutes,
       p_price_minor, not v_has_free)
    returning id into v_id;
  exception
    when check_violation then
      raise exception 'invalid_offering' using errcode = '22023';
    when foreign_key_violation then
      raise exception 'invalid_topic' using errcode = '22023';
  end;

  return v_id;
end;
$$;

revoke all on function public.create_offering(text, text, text, integer, bigint, uuid)
  from public, anon, authenticated;
grant execute on function public.create_offering(text, text, text, integer, bigint, uuid)
  to authenticated, service_role;

-- Availability ---------------------------------------------------------------
-- Weekly recurring windows in the provider's own timezone (profiles.timezone),
-- plus one-off blocks for time off. weekday follows Postgres: 0 = Sunday.

create table public.availability_rules (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete cascade,
  weekday smallint not null,
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  constraint availability_rules_weekday_valid check (weekday between 0 and 6),
  constraint availability_rules_time_order check (end_time > start_time),
  constraint availability_rules_unique unique (provider_id, weekday, start_time, end_time)
);

create index availability_rules_provider_idx on public.availability_rules (provider_id, weekday);

alter table public.availability_rules enable row level security;
revoke all on public.availability_rules from anon, authenticated;
grant select on public.availability_rules to anon, authenticated;
grant insert, update, delete on public.availability_rules to authenticated;

create policy availability_rules_select_public on public.availability_rules
  for select to anon, authenticated
  using (private.is_public_provider(provider_id));

create policy availability_rules_select_own on public.availability_rules
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy availability_rules_insert_own on public.availability_rules
  for insert to authenticated
  with check (provider_id = (select auth.uid()));

create policy availability_rules_update_own on public.availability_rules
  for update to authenticated
  using (provider_id = (select auth.uid()))
  with check (provider_id = (select auth.uid()));

create policy availability_rules_delete_own on public.availability_rules
  for delete to authenticated
  using (provider_id = (select auth.uid()));

-- Time off. Private to the provider: customers only ever see the resulting open
-- slots (get_open_slots), never the reason or the block itself.
create table public.availability_blocks (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_at timestamptz not null default now(),
  constraint availability_blocks_time_order check (ends_at > starts_at),
  constraint availability_blocks_reason_length check (reason is null or char_length(reason) <= 200)
);

create index availability_blocks_provider_idx on public.availability_blocks (provider_id, starts_at);

alter table public.availability_blocks enable row level security;
revoke all on public.availability_blocks from anon, authenticated;
grant select, insert, update, delete on public.availability_blocks to authenticated;

create policy availability_blocks_select_own on public.availability_blocks
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy availability_blocks_insert_own on public.availability_blocks
  for insert to authenticated
  with check (provider_id = (select auth.uid()));

create policy availability_blocks_update_own on public.availability_blocks
  for update to authenticated
  using (provider_id = (select auth.uid()))
  with check (provider_id = (select auth.uid()));

create policy availability_blocks_delete_own on public.availability_blocks
  for delete to authenticated
  using (provider_id = (select auth.uid()));
