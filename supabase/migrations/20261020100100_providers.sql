-- One On One migration 02: platform settings, topics, provider profiles.
--
-- A "provider" is a profile that has applied to sell paid conversations or
-- services. Approval is a moderation decision made by the server (service role or
-- an admin function), never by the client. Free messaging does NOT require being
-- a provider.

set search_path = public, extensions;

-- Platform settings ----------------------------------------------------------
-- A single row of business rules. Commercial terms are configuration, not code:
-- nothing here is hard-coded elsewhere. Money is in kobo (NGN minor units).
--
-- The values below are conservative placeholders, NOT approved commercial terms.
-- Commission and subscription pricing are product decisions still to be made:
--   * platform_fee_bps / service_fee_bps default to 0 (no commission).
--   * subscription_price_minor / subscription_period_days default to NULL, which
--     means "subscriptions are not on sale yet": the server refuses to start one.
-- Not readable by API roles other than admins; the server and SECURITY DEFINER
-- functions read it.

create table public.platform_settings (
  id boolean primary key default true,
  -- Commission on paid conversations and on paid services, in basis points.
  platform_fee_bps integer not null default 0,
  service_fee_bps integer not null default 0,
  -- Provider subscription (unlocks additional paid conversation offerings).
  subscription_price_minor bigint,
  subscription_period_days integer,
  -- Paid conversations.
  min_booking_lead_minutes integer not null default 30,
  payment_window_minutes integer not null default 15,
  free_cancellation_hours integer not null default 24,
  -- Hours after a completed session / accepted delivery before earnings become
  -- available to withdraw (the window in which a customer can raise a dispute).
  earnings_hold_hours integer not null default 24,
  -- Days after delivery before an unanswered service delivery completes itself.
  service_auto_release_days integer not null default 3,
  -- Free chats: messages a stranger may send before the recipient responds.
  request_message_limit integer not null default 3,
  -- Smallest withdrawal, in kobo (default NGN 1,000).
  min_payout_minor bigint not null default 100000,
  currency text not null default 'NGN',
  updated_at timestamptz not null default now(),
  constraint platform_settings_singleton check (id),
  constraint platform_settings_fee_range check (platform_fee_bps between 0 and 5000),
  constraint platform_settings_service_fee_range check (service_fee_bps between 0 and 5000),
  constraint platform_settings_sub_price check (subscription_price_minor is null or subscription_price_minor > 0),
  constraint platform_settings_sub_period check (subscription_period_days is null or subscription_period_days between 1 and 366),
  constraint platform_settings_sub_pair check ((subscription_price_minor is null) = (subscription_period_days is null)),
  constraint platform_settings_lead_range check (min_booking_lead_minutes >= 0),
  constraint platform_settings_window_range check (payment_window_minutes between 5 and 1440),
  constraint platform_settings_cancel_range check (free_cancellation_hours >= 0),
  constraint platform_settings_hold_range check (earnings_hold_hours >= 0),
  constraint platform_settings_release_range check (service_auto_release_days between 1 and 30),
  constraint platform_settings_request_range check (request_message_limit between 1 and 20),
  constraint platform_settings_min_payout_range check (min_payout_minor >= 0),
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
-- Curated list of conversation and service categories. Created and edited by
-- admins through the server; everyone can read the active ones. The starter list
-- below is editable by admins and is not a product decision.

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

insert into public.topics (slug, name) values
  ('career', 'Career'),
  ('business', 'Business'),
  ('technology', 'Technology'),
  ('education', 'Education'),
  ('creative', 'Creative'),
  ('relationships', 'Relationships'),
  ('personal-growth', 'Personal growth'),
  ('other', 'Other');

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
--   * The server (service role / owner / admin functions): any move between
--     valid statuses, which is how approval, rejection and suspension happen.
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

-- True when p_user is an approved provider that the CURRENT viewer may see and
-- book: the account is active, finished onboarding, has not hidden itself from
-- discovery, and neither side has blocked the other. Used by every public-read
-- policy and by booking and order creation, so a hidden, suspended or blocked
-- provider disappears everywhere at once. Signed-out visitors have no identity, so
-- the block check simply does not apply to them.
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
      and p.is_discoverable
      and p.username is not null
      and p.onboarding_completed_at is not null
      and not private.is_blocked_between((select auth.uid()), p_user)
  );
$$;

alter table public.provider_profiles enable row level security;
revoke all on public.provider_profiles from anon, authenticated;
-- Column-level read access, so internal moderation fields never leave the
-- database: reviewed_by (which admin decided) is readable by nobody through the
-- API. Clients must name their columns; "select *" is refused by design.
grant select (user_id, headline, about, languages, status, rating_count, rating_sum, created_at)
  on public.provider_profiles to anon;
grant select (user_id, headline, about, languages, status, rating_count, rating_sum, created_at,
              submitted_at, reviewed_at, rejection_reason, updated_at)
  on public.provider_profiles to authenticated;
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

-- Only active, onboarded accounts can apply to become a provider.
create policy provider_profiles_insert_own on public.provider_profiles
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = user_id and p.status = 'active' and p.onboarding_completed_at is not null
    )
  );

create policy provider_profiles_update_own on public.provider_profiles
  for update to authenticated
  using (user_id = (select auth.uid()) and status <> 'suspended')
  with check (user_id = (select auth.uid()));

-- Approved providers' profiles are public by design (that is what discovery is),
-- even for visitors who are not signed in.
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
