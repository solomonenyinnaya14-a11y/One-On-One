-- One On One migration 2/7: providers, topics, offerings, availability, settings.
--
-- A "provider" is a profile that has applied to be listed. Approval is a
-- moderation decision made by the server (service role), never by the client.

set search_path = public, extensions;

-- Platform settings ----------------------------------------------------------
-- A single row of business rules. Not readable by API roles; the server and
-- SECURITY DEFINER functions read it. Values below are conservative defaults
-- that must be reviewed before launch (see docs/database.md).

create table public.platform_settings (
  id boolean primary key default true,
  platform_fee_bps integer not null default 0,
  min_booking_lead_minutes integer not null default 30,
  payment_window_minutes integer not null default 15,
  free_cancellation_hours integer not null default 24,
  earnings_hold_hours integer not null default 0,
  currency text not null default 'NGN',
  updated_at timestamptz not null default now(),
  constraint platform_settings_singleton check (id),
  constraint platform_settings_fee_range check (platform_fee_bps between 0 and 5000),
  constraint platform_settings_lead_range check (min_booking_lead_minutes >= 0),
  constraint platform_settings_window_range check (payment_window_minutes between 5 and 1440),
  constraint platform_settings_cancel_range check (free_cancellation_hours >= 0),
  constraint platform_settings_hold_range check (earnings_hold_hours >= 0),
  constraint platform_settings_currency check (currency = 'NGN')
);

insert into public.platform_settings default values;

create trigger platform_settings_set_updated_at
  before update on public.platform_settings
  for each row execute function private.set_updated_at();

alter table public.platform_settings enable row level security;
revoke all on public.platform_settings from anon, authenticated;
grant select on public.platform_settings to authenticated;

create policy platform_settings_select_admin on public.platform_settings
  for select to authenticated
  using ((select private.is_admin()));

-- Topics ---------------------------------------------------------------------
-- Curated list of conversation topics. Created and edited by admins through the
-- server; everyone can read the active ones.

create table public.topics (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint topics_slug_key unique (slug),
  constraint topics_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 60),
  constraint topics_name_length check (char_length(btrim(name)) between 1 and 60)
);

create trigger topics_set_updated_at
  before update on public.topics
  for each row execute function private.set_updated_at();

alter table public.topics enable row level security;
revoke all on public.topics from anon, authenticated;
grant select on public.topics to anon, authenticated;

create policy topics_select_active on public.topics
  for select to anon, authenticated
  using (is_active);

-- Provider profiles ----------------------------------------------------------

create table public.provider_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  headline text,
  about text,
  languages text[] not null default '{}',
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id) on delete set null,
  rejection_reason text,
  -- Maintained by a trigger on reviews; never writable by users.
  rating_count integer not null default 0,
  rating_sum integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_profiles_headline_length check (headline is null or char_length(headline) <= 120),
  constraint provider_profiles_about_length check (about is null or char_length(about) <= 2000),
  constraint provider_profiles_languages_size check (cardinality(languages) <= 10),
  constraint provider_profiles_rejection_length check (rejection_reason is null or char_length(rejection_reason) <= 1000),
  constraint provider_profiles_status_valid
    check (status in ('draft', 'pending_review', 'approved', 'rejected', 'suspended')),
  constraint provider_profiles_complete_when_submitted
    check (
      status in ('draft', 'rejected')
      or (nullif(btrim(headline), '') is not null and nullif(btrim(about), '') is not null)
    ),
  constraint provider_profiles_rating_valid check (rating_count >= 0 and rating_sum >= 0)
);

create index provider_profiles_status_idx on public.provider_profiles (status);
create index provider_profiles_headline_trgm_idx
  on public.provider_profiles using gin (headline extensions.gin_trgm_ops);

create trigger provider_profiles_set_updated_at
  before update on public.provider_profiles
  for each row execute function private.set_updated_at();

-- Who may move a provider profile between statuses.
--   * Providers (API role "authenticated"): draft/rejected -> pending_review
--     (submit) and pending_review -> draft (withdraw). Nothing else.
--   * The server (service role / owner): any move between valid statuses, which
--     is how approval, rejection and suspension happen.
create function private.guard_provider_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if current_user in ('anon', 'authenticated') then
    if (old.status in ('draft', 'rejected') and new.status = 'pending_review') then
      new.submitted_at := now();
      new.rejection_reason := null;
    elsif (old.status = 'pending_review' and new.status = 'draft') then
      null;
    else
      raise exception 'provider_status_change_not_allowed: % -> %', old.status, new.status
        using errcode = '42501';
    end if;
  elsif new.status in ('approved', 'rejected') then
    new.reviewed_at := now();
  end if;

  return new;
end;
$$;

create trigger provider_profiles_guard_status
  before update on public.provider_profiles
  for each row execute function private.guard_provider_status();

-- True when a user is an approved provider whose account is active. Used by the
-- public-read policies so that suspended accounts disappear from discovery.
create function private.is_public_provider(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.provider_profiles pp
    join public.profiles p on p.id = pp.user_id
    where pp.user_id = p_user
      and pp.status = 'approved'
      and p.status = 'active'
  );
$$;

alter table public.provider_profiles enable row level security;
revoke all on public.provider_profiles from anon, authenticated;
grant select on public.provider_profiles to anon, authenticated;
-- Insert/update are limited to descriptive columns. Status (guarded by the
-- trigger above), review fields and rating counters are not user-writable.
grant insert (user_id, headline, about, languages) on public.provider_profiles to authenticated;
grant update (headline, about, languages, status) on public.provider_profiles to authenticated;

create policy provider_profiles_select_public on public.provider_profiles
  for select to anon, authenticated
  using (private.is_public_provider(user_id));

create policy provider_profiles_select_own on public.provider_profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy provider_profiles_select_admin on public.provider_profiles
  for select to authenticated
  using ((select private.is_admin()));

create policy provider_profiles_insert_own on public.provider_profiles
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy provider_profiles_update_own on public.provider_profiles
  for update to authenticated
  using (user_id = (select auth.uid()) and status <> 'suspended')
  with check (user_id = (select auth.uid()));

-- Approved providers' profiles are public by design (that is what discovery is).
create policy profiles_select_public_providers on public.profiles
  for select to anon, authenticated
  using (private.is_public_provider(id));

-- Provider topics ------------------------------------------------------------

create table public.provider_topics (
  provider_id uuid not null references public.provider_profiles (user_id) on delete cascade,
  topic_id uuid not null references public.topics (id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (provider_id, topic_id)
);

create index provider_topics_topic_id_idx on public.provider_topics (topic_id);

create function private.limit_provider_topics()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.provider_topics t where t.provider_id = new.provider_id) >= 10 then
    raise exception 'too_many_topics' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger provider_topics_limit
  before insert on public.provider_topics
  for each row execute function private.limit_provider_topics();

alter table public.provider_topics enable row level security;
revoke all on public.provider_topics from anon, authenticated;
grant select on public.provider_topics to anon, authenticated;
grant insert, delete on public.provider_topics to authenticated;

create policy provider_topics_select_public on public.provider_topics
  for select to anon, authenticated
  using (private.is_public_provider(provider_id));

create policy provider_topics_select_own on public.provider_topics
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy provider_topics_insert_own on public.provider_topics
  for insert to authenticated
  with check (provider_id = (select auth.uid()));

create policy provider_topics_delete_own on public.provider_topics
  for delete to authenticated
  using (provider_id = (select auth.uid()));

-- Offerings ------------------------------------------------------------------
-- What a provider sells: a text or voice conversation of a fixed length at a
-- fixed price. Prices are integers in kobo (NGN minor units): never floats.
-- A booking copies these values at booking time, so later edits do not change
-- existing bookings.

create table public.offerings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete cascade,
  kind text not null,
  title text not null,
  description text,
  duration_minutes integer not null,
  price_minor bigint not null,
  currency text not null default 'NGN',
  is_active boolean not null default true,
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

create trigger offerings_set_updated_at
  before update on public.offerings
  for each row execute function private.set_updated_at();

alter table public.offerings enable row level security;
revoke all on public.offerings from anon, authenticated;
grant select on public.offerings to anon, authenticated;
grant insert (provider_id, kind, title, description, duration_minutes, price_minor, is_active)
  on public.offerings to authenticated;
grant update (title, description, duration_minutes, price_minor, is_active)
  on public.offerings to authenticated;
grant delete on public.offerings to authenticated;

create policy offerings_select_public on public.offerings
  for select to anon, authenticated
  using (is_active and private.is_public_provider(provider_id));

create policy offerings_select_own on public.offerings
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy offerings_insert_own on public.offerings
  for insert to authenticated
  with check (provider_id = (select auth.uid()));

create policy offerings_update_own on public.offerings
  for update to authenticated
  using (provider_id = (select auth.uid()))
  with check (provider_id = (select auth.uid()));

create policy offerings_delete_own on public.offerings
  for delete to authenticated
  using (provider_id = (select auth.uid()));

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
