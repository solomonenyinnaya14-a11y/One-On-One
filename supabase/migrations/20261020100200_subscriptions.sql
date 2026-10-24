-- One On One migration 03: provider subscriptions and the gateway event inbox.
--
-- Product rule (from the founder's direction):
--   * Every provider gets ONE paid-conversation offering for free.
--   * Additional offerings need an ACTIVE subscription.
--   * When a subscription ends, the extra offerings stop accepting NEW bookings.
--     Nothing is deleted. Existing bookings, messages, history, earnings and
--     withdrawals are untouched.
--
-- Entitlement is decided here, in the database, from authoritative rows that only
-- the server can write. A "payment success" screen in the browser never grants
-- anything: the server verifies the gateway's event first (see migration 08).

set search_path = public, extensions;

-- Webhook inbox ----------------------------------------------------------------
-- One row per distinct event from the payment gateway. The unique (gateway,
-- event_id) makes processing idempotent: a replayed webhook is detected and
-- skipped. Only events whose signature the server verified are ever stored.

create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  gateway text not null,
  event_id text not null,
  event_type text not null,
  signature_verified boolean not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_result text,
  constraint payment_events_event_key unique (gateway, event_id),
  constraint payment_events_signature_required check (signature_verified),
  constraint payment_events_gateway_format check (gateway ~ '^[a-z0-9_]{2,30}$'),
  constraint payment_events_event_id_length check (char_length(event_id) between 1 and 200)
);

alter table public.payment_events enable row level security;
revoke all on public.payment_events from anon, authenticated;
-- No policies and no grants: only the server can touch this table.

-- Subscriptions ------------------------------------------------------------------
-- One row per provider. The gateway's identifiers are never readable by clients.

create table public.provider_subscriptions (
  provider_id uuid primary key references public.provider_profiles (user_id) on delete restrict,
  -- active   : paid up (entitled until current_period_end)
  -- past_due : the latest renewal failed; still entitled until current_period_end
  -- ended    : the paid period finished and was not renewed
  -- revoked  : removed by an administrator (for example after a refund or abuse)
  status text not null default 'active',
  gateway text not null,
  gateway_customer_code text,
  gateway_subscription_code text,
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  -- True once the provider (or the gateway) has stopped renewal. Access continues
  -- until current_period_end.
  cancel_at_period_end boolean not null default false,
  -- Timestamp of the newest gateway event applied. Older events that arrive late
  -- are ignored for state changes, so out-of-order delivery cannot go backwards.
  last_event_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_subscriptions_status_valid
    check (status in ('active', 'past_due', 'ended', 'revoked')),
  constraint provider_subscriptions_gateway_format check (gateway ~ '^[a-z0-9_]{2,30}$'),
  constraint provider_subscriptions_period_valid check (current_period_end > current_period_start)
);

create trigger provider_subscriptions_set_updated_at
  before update on public.provider_subscriptions
  for each row execute function private.set_updated_at();

create trigger provider_subscriptions_forbid_delete
  before delete on public.provider_subscriptions
  for each row execute function private.forbid_delete();

alter table public.provider_subscriptions enable row level security;
revoke all on public.provider_subscriptions from anon, authenticated;
grant select (provider_id, status, current_period_start, current_period_end,
              cancel_at_period_end, created_at, updated_at)
  on public.provider_subscriptions to authenticated;

create policy provider_subscriptions_select_own on public.provider_subscriptions
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy provider_subscriptions_select_admin on public.provider_subscriptions
  for select to authenticated
  using ((select private.is_admin()));

-- Every successful subscription payment, one row each. The unique (gateway,
-- reference) stops a retried event from being counted twice.
create table public.subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  gateway text not null,
  reference text not null,
  amount_minor bigint not null,
  currency text not null default 'NGN',
  period_start timestamptz not null,
  period_end timestamptz not null,
  created_at timestamptz not null default now(),
  constraint subscription_invoices_reference_key unique (gateway, reference),
  constraint subscription_invoices_amount_valid check (amount_minor > 0),
  constraint subscription_invoices_currency_valid check (currency = 'NGN'),
  constraint subscription_invoices_period_valid check (period_end > period_start)
);

create index subscription_invoices_provider_idx
  on public.subscription_invoices (provider_id, created_at desc);

create trigger subscription_invoices_append_only
  before update or delete on public.subscription_invoices
  for each row execute function private.forbid_change();

alter table public.subscription_invoices enable row level security;
revoke all on public.subscription_invoices from anon, authenticated;
grant select (id, provider_id, amount_minor, currency, period_start, period_end, created_at)
  on public.subscription_invoices to authenticated;

create policy subscription_invoices_select_own on public.subscription_invoices
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy subscription_invoices_select_admin on public.subscription_invoices
  for select to authenticated
  using ((select private.is_admin()));

-- Entitlement ------------------------------------------------------------------
-- A provider is entitled while their paid period has not finished and the
-- subscription has not been revoked. This is evaluated against the clock every
-- time, so an expired subscription stops granting access even if no cleanup job
-- has run yet. A cancelled-but-not-yet-ended subscription is still entitled.
create function private.has_active_subscription(p_provider uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.provider_subscriptions s
    where s.provider_id = p_provider
      and s.status in ('active', 'past_due')
      and s.current_period_end > now()
  );
$$;

-- Public, read-only answer for the signed-in provider's own account page.
create function public.my_subscription_status()
returns table (
  entitled boolean,
  status text,
  current_period_end timestamptz,
  cancel_at_period_end boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_active_subscription((select auth.uid())),
         s.status,
         s.current_period_end,
         s.cancel_at_period_end
    from (select 1) one
    left join public.provider_subscriptions s on s.provider_id = (select auth.uid());
$$;

revoke all on function public.my_subscription_status() from public, anon, authenticated;
grant execute on function public.my_subscription_status() to authenticated, service_role;
