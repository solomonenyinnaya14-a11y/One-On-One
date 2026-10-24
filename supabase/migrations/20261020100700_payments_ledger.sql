-- One On One migration 08: payments, ledger, refunds, earnings, payouts, billing.
--
-- Principles
--   * No card data is ever stored here. Card details go straight to the payment
--     gateway; we keep only references, amounts and statuses.
--   * Nothing the browser says about money is trusted. A payment is created from
--     the booking's (or order's) own price, and it only becomes "succeeded"
--     through record_payment_success(), which the SERVER calls after verifying
--     the gateway's webhook signature and re-checking the transaction with the
--     gateway. The database then re-checks the amount against the booking.
--   * Every money-moving function below is executable ONLY by service_role (the
--     server). Participant-callable functions (cancel, dispute, accept delivery,
--     start/deliver an order) work out every amount themselves.
--   * Idempotency is built in at every step (unique webhook event ids, unique
--     payment references, unique ledger idempotency keys, unique refund keys), so
--     a retried webhook or a double click can never create a second charge record
--     or a second ledger posting.
--   * The ledger is double-entry and append-only: every transaction balances to
--     zero and nothing is ever updated or deleted. Mistakes are fixed with
--     reversing entries.
--
-- Concepts kept separate on purpose
--   payment    : a customer paid the gateway for a booking or service order.
--   held funds : money the platform is holding for a paid item that is not yet
--                released. This is an internal bookkeeping label; it does NOT
--                claim any legal escrow or wallet status (see docs/payments.md).
--   earnings   : the provider's share of a payment. PENDING until the session or
--                delivery is complete and the hold window has passed, then
--                AVAILABLE to withdraw, then IN_PAYOUT, then PAID_OUT.
--   payout     : a withdrawal the provider requested for available earnings.
--
-- Money flow (all amounts in kobo)
--   payment captured : debit gateway_clearing / credit held_funds
--   earnings released: debit held_funds / credit provider_payable + platform_revenue
--   refund issued    : debit held_funds / credit gateway_clearing
--   payout requested : debit provider_payable / credit payouts_pending
--   payout paid      : debit payouts_pending / credit gateway_clearing
--   payout failed    : debit payouts_pending / credit provider_payable
--   subscription paid: debit gateway_clearing / credit platform_revenue

set search_path = public, extensions;

-- Payments ---------------------------------------------------------------------

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  -- Exactly one target: a paid conversation booking OR a service order.
  booking_id uuid references public.bookings (id) on delete restrict,
  service_order_id uuid references public.service_orders (id) on delete restrict,
  customer_id uuid not null references public.profiles (id) on delete restrict,
  gateway text not null,
  -- Our own unique reference, generated server-side and sent to the gateway.
  reference text not null,
  gateway_transaction_id text,
  amount_minor bigint not null,
  currency text not null default 'NGN',
  status text not null default 'initialized',
  failure_reason text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_one_target check (num_nonnulls(booking_id, service_order_id) = 1),
  constraint payments_gateway_format check (gateway ~ '^[a-z0-9_]{2,30}$'),
  constraint payments_reference_length check (char_length(reference) between 8 and 100),
  constraint payments_reference_key unique (gateway, reference),
  constraint payments_amount_valid check (amount_minor between 100 and 100000000),
  constraint payments_currency_valid check (currency = 'NGN'),
  constraint payments_status_valid check (status in ('initialized', 'succeeded', 'failed', 'cancelled')),
  constraint payments_success_has_details
    check (status <> 'succeeded' or (gateway_transaction_id is not null and paid_at is not null))
);

create unique index payments_gateway_txn_key
  on public.payments (gateway, gateway_transaction_id)
  where gateway_transaction_id is not null;
create index payments_booking_idx on public.payments (booking_id) where booking_id is not null;
create index payments_service_order_idx on public.payments (service_order_id) where service_order_id is not null;
create index payments_customer_idx on public.payments (customer_id, created_at desc);

create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function private.set_updated_at();

-- A payment can only be created for an unpaid booking or order, by its own
-- customer, for exactly the item's price.
create function private.guard_payment_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_customer uuid;
  v_price bigint;
  v_currency text;
  v_status text;
begin
  if new.status <> 'initialized' then
    raise exception 'payment_must_start_initialized' using errcode = '23514';
  end if;

  if new.booking_id is not null then
    select b.customer_id, b.price_minor, b.currency, b.status
      into v_customer, v_price, v_currency, v_status
      from public.bookings b where b.id = new.booking_id;
    if not found or v_status <> 'pending_payment' then
      raise exception 'booking_not_payable' using errcode = '23514';
    end if;
  else
    select o.customer_id, o.price_minor, o.currency, o.status
      into v_customer, v_price, v_currency, v_status
      from public.service_orders o where o.id = new.service_order_id;
    if not found or v_status <> 'pending_payment' then
      raise exception 'order_not_payable' using errcode = '23514';
    end if;
  end if;

  if v_customer <> new.customer_id then
    raise exception 'payment_customer_mismatch' using errcode = '42501';
  end if;
  if new.amount_minor <> v_price or new.currency <> v_currency then
    raise exception 'payment_amount_mismatch' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger payments_guard_insert
  before insert on public.payments
  for each row execute function private.guard_payment_insert();

-- Identity fields are frozen. A payment that was marked failed or cancelled may
-- still succeed (gateways do report late successes, and the money is real), but
-- a succeeded payment is final.
create function private.guard_payment_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.booking_id, new.service_order_id, new.customer_id, new.gateway, new.reference,
      new.amount_minor, new.currency, new.created_at)
     is distinct from
     (old.booking_id, old.service_order_id, old.customer_id, old.gateway, old.reference,
      old.amount_minor, old.currency, old.created_at)
  then
    raise exception 'payment_is_immutable' using errcode = '42501';
  end if;

  if old.status = 'succeeded'
     and (new.status is distinct from old.status
          or new.gateway_transaction_id is distinct from old.gateway_transaction_id
          or new.paid_at is distinct from old.paid_at) then
    raise exception 'payment_is_final' using errcode = '42501';
  end if;

  if new.status is distinct from old.status
     and not (
       (old.status = 'initialized' and new.status in ('succeeded', 'failed', 'cancelled'))
       or (old.status in ('failed', 'cancelled') and new.status = 'succeeded')
     ) then
    raise exception 'invalid_payment_transition: % -> %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger payments_guard_update
  before update on public.payments
  for each row execute function private.guard_payment_update();

create trigger payments_forbid_delete
  before delete on public.payments
  for each row execute function private.forbid_delete();

alter table public.payments enable row level security;
revoke all on public.payments from anon, authenticated;
-- Customers see their own payments, without gateway identifiers.
grant select (id, booking_id, service_order_id, amount_minor, currency, status, paid_at, created_at)
  on public.payments to authenticated;

create policy payments_select_own on public.payments
  for select to authenticated
  using (customer_id = (select auth.uid()));

create policy payments_select_admin on public.payments
  for select to authenticated
  using ((select private.is_admin()));

-- Refunds ----------------------------------------------------------------------
-- A refund row is a request ("outbox"). The server picks up pending rows, calls
-- the gateway, and reports the result through record_refund_result(). A booking
-- or order is only marked REFUNDED after the gateway confirms.

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete restrict,
  booking_id uuid references public.bookings (id) on delete restrict,
  service_order_id uuid references public.service_orders (id) on delete restrict,
  customer_id uuid not null references public.profiles (id) on delete restrict,
  amount_minor bigint not null,
  reason text not null,
  status text not null default 'pending',
  idempotency_key text not null,
  gateway_refund_id text,
  failure_reason text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint refunds_one_target check (num_nonnulls(booking_id, service_order_id) = 1),
  constraint refunds_amount_valid check (amount_minor between 100 and 100000000),
  constraint refunds_reason_valid
    check (reason in ('cancelled_by_customer', 'cancelled_by_provider', 'session_not_held',
                      'booking_unavailable', 'duplicate_payment', 'dispute_resolved',
                      'service_not_delivered', 'admin')),
  constraint refunds_status_valid check (status in ('pending', 'succeeded', 'failed')),
  constraint refunds_idempotency_key unique (idempotency_key)
);

create index refunds_payment_idx on public.refunds (payment_id);
create index refunds_booking_idx on public.refunds (booking_id) where booking_id is not null;
create index refunds_service_order_idx on public.refunds (service_order_id) where service_order_id is not null;
create index refunds_pending_idx on public.refunds (created_at) where status = 'pending';
create index refunds_customer_idx on public.refunds (customer_id, created_at desc);

create trigger refunds_set_updated_at
  before update on public.refunds
  for each row execute function private.set_updated_at();

-- Refunds can never add up to more than the payment they refund.
create function private.guard_refund_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_payment public.payments%rowtype;
  v_already bigint;
begin
  select * into v_payment from public.payments p where p.id = new.payment_id for update;
  if not found or v_payment.status <> 'succeeded' then
    raise exception 'refund_requires_succeeded_payment' using errcode = '23514';
  end if;
  if v_payment.booking_id is distinct from new.booking_id
     or v_payment.service_order_id is distinct from new.service_order_id
     or v_payment.customer_id <> new.customer_id then
    raise exception 'refund_payment_mismatch' using errcode = '23514';
  end if;

  select coalesce(sum(r.amount_minor), 0) into v_already
    from public.refunds r
   where r.payment_id = new.payment_id and r.status in ('pending', 'succeeded');

  if v_already + new.amount_minor > v_payment.amount_minor then
    raise exception 'refund_exceeds_payment' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger refunds_guard_insert
  before insert on public.refunds
  for each row execute function private.guard_refund_insert();

create function private.guard_refund_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.payment_id, new.booking_id, new.service_order_id, new.customer_id, new.amount_minor,
      new.reason, new.idempotency_key, new.created_at)
     is distinct from
     (old.payment_id, old.booking_id, old.service_order_id, old.customer_id, old.amount_minor,
      old.reason, old.idempotency_key, old.created_at)
  then
    raise exception 'refund_is_immutable' using errcode = '42501';
  end if;
  if old.status <> 'pending' and new.status is distinct from old.status then
    raise exception 'refund_is_final' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger refunds_guard_update
  before update on public.refunds
  for each row execute function private.guard_refund_update();

create trigger refunds_forbid_delete
  before delete on public.refunds
  for each row execute function private.forbid_delete();

alter table public.refunds enable row level security;
revoke all on public.refunds from anon, authenticated;
grant select (id, payment_id, booking_id, service_order_id, amount_minor, reason, status,
              created_at, processed_at)
  on public.refunds to authenticated;

create policy refunds_select_own on public.refunds
  for select to authenticated
  using (customer_id = (select auth.uid()));

create policy refunds_select_admin on public.refunds
  for select to authenticated
  using ((select private.is_admin()));

-- Queues a full refund of a payment. Safe to call twice with the same key.
create function private.queue_refund(p_payment uuid, p_reason text, p_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.payments%rowtype;
  v_id uuid;
begin
  select * into v_pay from public.payments p where p.id = p_payment;
  if not found then
    raise exception 'payment_not_found' using errcode = 'P0002';
  end if;

  insert into public.refunds
    (payment_id, booking_id, service_order_id, customer_id, amount_minor, reason, idempotency_key)
  values
    (v_pay.id, v_pay.booking_id, v_pay.service_order_id, v_pay.customer_id, v_pay.amount_minor,
     p_reason, p_key)
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    select r.id into v_id from public.refunds r where r.idempotency_key = p_key;
  end if;
  return v_id;
end;
$$;

-- Ledger -----------------------------------------------------------------------

create table public.ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  -- Posting the same business event twice is impossible: the key is unique.
  idempotency_key text not null,
  subject_kind text,
  subject_id uuid,
  payment_id uuid references public.payments (id) on delete restrict,
  refund_id uuid references public.refunds (id) on delete restrict,
  payout_id uuid,
  created_at timestamptz not null default now(),
  constraint ledger_transactions_key unique (idempotency_key),
  constraint ledger_transactions_kind_valid
    check (kind in ('payment_captured', 'earnings_released', 'refund_issued',
                    'payout_requested', 'payout_paid', 'payout_failed', 'subscription_payment')),
  constraint ledger_transactions_subject_valid
    check ((subject_kind is null) = (subject_id is null)
           and (subject_kind is null or subject_kind in ('booking', 'service_order', 'subscription')))
);

create index ledger_transactions_subject_idx on public.ledger_transactions (subject_kind, subject_id);

create table public.ledger_entries (
  id bigint generated always as identity primary key,
  transaction_id uuid not null references public.ledger_transactions (id) on delete restrict,
  kind text not null,
  account text not null,
  direction text not null,
  amount_minor bigint not null,
  -- The provider, for accounts that belong to one provider.
  owner_id uuid references public.profiles (id) on delete restrict,
  subject_kind text,
  subject_id uuid,
  created_at timestamptz not null default now(),
  constraint ledger_entries_account_valid
    check (account in ('gateway_clearing', 'held_funds', 'provider_payable', 'platform_revenue', 'payouts_pending')),
  constraint ledger_entries_direction_valid check (direction in ('debit', 'credit')),
  constraint ledger_entries_amount_valid check (amount_minor > 0),
  constraint ledger_entries_owner_rule
    check ((account in ('provider_payable', 'payouts_pending')) = (owner_id is not null)),
  constraint ledger_entries_subject_pair check ((subject_kind is null) = (subject_id is null)),
  constraint ledger_entries_subject_kind_valid
    check (subject_kind is null or subject_kind in ('booking', 'service_order', 'subscription')),
  constraint ledger_entries_held_has_subject check (account <> 'held_funds' or subject_id is not null)
);

create index ledger_entries_transaction_idx on public.ledger_entries (transaction_id);
create index ledger_entries_account_idx on public.ledger_entries (account, owner_id);
create index ledger_entries_subject_idx on public.ledger_entries (subject_kind, subject_id);

-- Append-only: no updates, deletes or truncates, for any role.
create trigger ledger_transactions_append_only
  before update or delete on public.ledger_transactions
  for each row execute function private.forbid_change();
create trigger ledger_entries_append_only
  before update or delete on public.ledger_entries
  for each row execute function private.forbid_change();
create trigger ledger_transactions_no_truncate
  before truncate on public.ledger_transactions
  for each statement execute function private.forbid_truncate();
create trigger ledger_entries_no_truncate
  before truncate on public.ledger_entries
  for each statement execute function private.forbid_truncate();

-- Every transaction's entries must arrive in ONE statement and balance exactly
-- (debits = credits), with at least two entries. Checked immediately, not at
-- commit, so an unbalanced posting fails on the spot.
create function private.check_ledger_batch_balanced()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from (
      select n.transaction_id,
             sum(case when n.direction = 'debit' then n.amount_minor else 0 end) as debits,
             sum(case when n.direction = 'credit' then n.amount_minor else 0 end) as credits,
             count(*) as entries
        from new_rows n
       group by n.transaction_id
    ) b
    where b.debits <> b.credits
       or b.entries < 2
       or b.entries <> (select count(*) from public.ledger_entries x where x.transaction_id = b.transaction_id)
  ) then
    raise exception 'ledger_transaction_not_balanced' using errcode = '23514';
  end if;
  return null;
end;
$$;

create trigger ledger_entries_balanced
  after insert on public.ledger_entries
  referencing new table as new_rows
  for each statement execute function private.check_ledger_batch_balanced();

alter table public.ledger_transactions enable row level security;
revoke all on public.ledger_transactions from anon, authenticated;

alter table public.ledger_entries enable row level security;
revoke all on public.ledger_entries from anon, authenticated;
-- Providers can see the ledger lines that belong to them (their own earnings and
-- payouts) and nothing else. Customers and the platform's own accounts are
-- never readable through the API.
grant select (id, kind, account, direction, amount_minor, subject_kind, subject_id, created_at, owner_id)
  on public.ledger_entries to authenticated;

create policy ledger_entries_select_owner on public.ledger_entries
  for select to authenticated
  using (owner_id = (select auth.uid()));

-- Posts one balanced transaction. Returns false (and changes nothing) when this
-- idempotency key has already been posted.
create function private.post_ledger(
  p_kind text,
  p_key text,
  p_subject_kind text,
  p_subject_id uuid,
  p_payment uuid,
  p_refund uuid,
  p_payout uuid,
  p_entries jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx uuid;
begin
  insert into public.ledger_transactions
    (kind, idempotency_key, subject_kind, subject_id, payment_id, refund_id, payout_id)
  values (p_kind, p_key, p_subject_kind, p_subject_id, p_payment, p_refund, p_payout)
  on conflict (idempotency_key) do nothing
  returning id into v_tx;

  if v_tx is null then
    return false;
  end if;

  insert into public.ledger_entries
    (transaction_id, kind, account, direction, amount_minor, owner_id, subject_kind, subject_id)
  select v_tx, p_kind, x.account, x.direction, x.amount_minor, x.owner_id, p_subject_kind, p_subject_id
    from jsonb_to_recordset(p_entries)
         as x(account text, direction text, amount_minor bigint, owner_id uuid);

  return true;
end;
$$;

-- Money currently held for one booking or order (captured, not yet released or
-- refunded).
create function private.held_balance(p_kind text, p_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(case e.direction when 'credit' then e.amount_minor else -e.amount_minor end), 0)::bigint
    from public.ledger_entries e
   where e.account = 'held_funds' and e.subject_kind = p_kind and e.subject_id = p_id;
$$;

-- Payout destinations, payouts and earnings ----------------------------------------
-- Only a gateway "recipient code" and a masked account are stored. The full bank
-- account number is sent to the gateway and never kept here.

create table public.payout_accounts (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  gateway text not null,
  recipient_code text not null,
  bank_name text not null,
  account_name text not null,
  account_last4 text not null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payout_accounts_provider_key unique (provider_id),
  constraint payout_accounts_gateway_format check (gateway ~ '^[a-z0-9_]{2,30}$'),
  constraint payout_accounts_last4_format check (account_last4 ~ '^[0-9]{4}$'),
  constraint payout_accounts_text_length
    check (char_length(bank_name) between 1 and 100 and char_length(account_name) between 1 and 150
           and char_length(recipient_code) between 1 and 100)
);

create trigger payout_accounts_set_updated_at
  before update on public.payout_accounts
  for each row execute function private.set_updated_at();

alter table public.payout_accounts enable row level security;
revoke all on public.payout_accounts from anon, authenticated;
-- recipient_code (the gateway's handle for the account) is not readable.
grant select (id, provider_id, bank_name, account_name, account_last4, verified_at, created_at)
  on public.payout_accounts to authenticated;

create policy payout_accounts_select_own on public.payout_accounts
  for select to authenticated
  using (provider_id = (select auth.uid()));

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  payout_account_id uuid not null references public.payout_accounts (id) on delete restrict,
  amount_minor bigint not null,
  -- Transfer fee charged by the gateway, recorded for reconciliation.
  fee_minor bigint not null default 0,
  currency text not null default 'NGN',
  status text not null default 'requested',
  idempotency_key text not null,
  gateway text not null,
  gateway_transfer_id text,
  failure_reason text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payouts_amount_valid check (amount_minor > 0),
  constraint payouts_fee_valid check (fee_minor >= 0),
  constraint payouts_currency_valid check (currency = 'NGN'),
  constraint payouts_status_valid check (status in ('requested', 'processing', 'paid', 'failed')),
  constraint payouts_idempotency_key unique (idempotency_key)
);

create unique index payouts_gateway_transfer_key
  on public.payouts (gateway, gateway_transfer_id) where gateway_transfer_id is not null;
create index payouts_provider_idx on public.payouts (provider_id, requested_at desc);

create trigger payouts_set_updated_at
  before update on public.payouts
  for each row execute function private.set_updated_at();

create function private.guard_payout_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.provider_id, new.payout_account_id, new.amount_minor, new.currency,
      new.idempotency_key, new.created_at)
     is distinct from
     (old.provider_id, old.payout_account_id, old.amount_minor, old.currency,
      old.idempotency_key, old.created_at)
  then
    raise exception 'payout_is_immutable' using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not (
       (old.status = 'requested' and new.status in ('processing', 'paid', 'failed'))
       or (old.status = 'processing' and new.status in ('paid', 'failed'))
     ) then
    raise exception 'invalid_payout_transition: % -> %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger payouts_guard_update
  before update on public.payouts
  for each row execute function private.guard_payout_update();

create trigger payouts_forbid_delete
  before delete on public.payouts
  for each row execute function private.forbid_delete();

alter table public.payouts enable row level security;
revoke all on public.payouts from anon, authenticated;
grant select (id, provider_id, amount_minor, fee_minor, currency, status, requested_at,
              processed_at, created_at)
  on public.payouts to authenticated;

create policy payouts_select_own on public.payouts
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy payouts_select_admin on public.payouts
  for select to authenticated
  using ((select private.is_admin()));

-- One row per paid booking or service order. The status says exactly where the
-- provider's money is:
--   pending   : paid by the customer, not yet released (session or delivery not
--               finished, or the hold window has not passed)
--   disputed  : frozen while an administrator decides a dispute
--   available : released; can be withdrawn
--   in_payout : included in a withdrawal that is being processed
--   paid_out  : withdrawn
--   void      : refunded to the customer; the provider earns nothing
create table public.provider_earnings (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  source_kind text not null,
  source_id uuid not null,
  gross_minor bigint not null,
  fee_minor bigint not null,
  net_minor bigint not null,
  currency text not null default 'NGN',
  status text not null default 'pending',
  -- Set when the item completes: earnings become available at this time.
  release_after timestamptz,
  released_at timestamptz,
  release_reason text,
  payout_id uuid references public.payouts (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_earnings_source_key unique (source_kind, source_id),
  constraint provider_earnings_source_kind_valid check (source_kind in ('booking', 'service_order')),
  constraint provider_earnings_amounts_valid
    check (gross_minor > 0 and fee_minor >= 0 and net_minor = gross_minor - fee_minor and net_minor > 0),
  constraint provider_earnings_currency_valid check (currency = 'NGN'),
  constraint provider_earnings_status_valid
    check (status in ('pending', 'disputed', 'available', 'in_payout', 'paid_out', 'void')),
  constraint provider_earnings_payout_rule check ((status in ('in_payout', 'paid_out')) = (payout_id is not null)),
  constraint provider_earnings_released_rule
    check ((status in ('available', 'in_payout', 'paid_out')) = (released_at is not null)),
  constraint provider_earnings_reason_valid
    check (release_reason is null or release_reason in
           ('completed', 'late_cancellation', 'delivery_accepted', 'auto_released', 'dispute_resolved'))
);

create index provider_earnings_provider_idx on public.provider_earnings (provider_id, status);
create index provider_earnings_due_idx on public.provider_earnings (release_after)
  where status = 'pending' and release_after is not null;
create index provider_earnings_payout_idx on public.provider_earnings (payout_id) where payout_id is not null;

create trigger provider_earnings_set_updated_at
  before update on public.provider_earnings
  for each row execute function private.set_updated_at();

create trigger provider_earnings_forbid_delete
  before delete on public.provider_earnings
  for each row execute function private.forbid_delete();

alter table public.provider_earnings enable row level security;
revoke all on public.provider_earnings from anon, authenticated;
grant select (id, provider_id, source_kind, source_id, gross_minor, fee_minor, net_minor, currency,
              status, release_after, released_at, release_reason, payout_id, created_at)
  on public.provider_earnings to authenticated;

create policy provider_earnings_select_own on public.provider_earnings
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy provider_earnings_select_admin on public.provider_earnings
  for select to authenticated
  using ((select private.is_admin()));

-- The provider's earnings dashboard numbers, calculated by the database from the
-- earnings rows (never from anything the browser sends).
create function public.my_earnings_summary()
returns table (
  pending_minor bigint,
  available_minor bigint,
  in_payout_minor bigint,
  withdrawn_minor bigint,
  total_minor bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(e.net_minor) filter (where e.status in ('pending', 'disputed')), 0)::bigint,
         coalesce(sum(e.net_minor) filter (where e.status = 'available'), 0)::bigint,
         coalesce(sum(e.net_minor) filter (where e.status = 'in_payout'), 0)::bigint,
         coalesce(sum(e.net_minor) filter (where e.status = 'paid_out'), 0)::bigint,
         coalesce(sum(e.net_minor) filter (where e.status <> 'void'), 0)::bigint
    from public.provider_earnings e
   where e.provider_id = (select auth.uid());
$$;

-- Releasing earnings --------------------------------------------------------------

-- Moves a paid item's held funds to the provider (net) and the platform (fee) and
-- makes the earnings available. Safe to call twice: the second call does nothing.
create function private.release_earnings(p_kind text, p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e public.provider_earnings%rowtype;
  v_entries jsonb;
begin
  select * into v_e from public.provider_earnings e
   where e.source_kind = p_kind and e.source_id = p_id
   for update;
  if not found then
    raise exception 'earnings_not_found' using errcode = 'P0002';
  end if;
  if v_e.status <> 'pending' then
    return;
  end if;
  if private.held_balance(p_kind, p_id) < v_e.gross_minor then
    raise exception 'held_funds_insufficient' using errcode = '23514';
  end if;

  v_entries := jsonb_build_array(
    jsonb_build_object('account', 'held_funds', 'direction', 'debit', 'amount_minor', v_e.gross_minor),
    jsonb_build_object('account', 'provider_payable', 'direction', 'credit',
                       'amount_minor', v_e.net_minor, 'owner_id', v_e.provider_id)
  );
  if v_e.fee_minor > 0 then
    v_entries := v_entries || jsonb_build_array(
      jsonb_build_object('account', 'platform_revenue', 'direction', 'credit', 'amount_minor', v_e.fee_minor)
    );
  end if;

  perform private.post_ledger('earnings_released', 'release:' || p_kind || ':' || p_id,
                              p_kind, p_id, null, null, null, v_entries);

  update public.provider_earnings
     set status = 'available', released_at = now(), release_reason = p_reason
   where id = v_e.id;
end;
$$;

-- Starts the hold window for an item that has just finished. With a hold of zero
-- hours the earnings are released straight away.
create function private.queue_release(p_kind text, p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hold integer;
begin
  select s.earnings_hold_hours into v_hold from public.platform_settings s;

  update public.provider_earnings
     set release_after = now() + v_hold * interval '1 hour',
         release_reason = p_reason
   where source_kind = p_kind and source_id = p_id and status = 'pending';

  if v_hold = 0 then
    perform private.release_earnings(p_kind, p_id, p_reason);
  end if;
end;
$$;

-- Run on a schedule by the server: releases every earning whose hold has passed
-- and that has not been disputed.
create function public.release_due_earnings()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e record;
  v_count integer := 0;
begin
  for v_e in
    select e.source_kind, e.source_id, coalesce(e.release_reason, 'completed') as reason
      from public.provider_earnings e
     where e.status = 'pending' and e.release_after is not null and e.release_after <= now()
     order by e.release_after
     for update skip locked
  loop
    perform private.release_earnings(v_e.source_kind, v_e.source_id, v_e.reason);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Server functions: payments ----------------------------------------------------

-- Step 1 of paying: the server asks for a payment for a booking or service order
-- on behalf of the signed-in customer it has already authenticated. The amount
-- comes from the item, never from the request. Calling again with the same
-- reference returns the same payment.
create function public.create_payment(
  p_kind text,
  p_target_id uuid,
  p_customer_id uuid,
  p_gateway text,
  p_reference text
)
returns table (out_payment_id uuid, out_amount_minor bigint, out_currency text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b public.bookings%rowtype;
  v_o public.service_orders%rowtype;
  v_p public.payments%rowtype;
begin
  if p_kind not in ('booking', 'service_order') then
    raise exception 'invalid_payment_target' using errcode = '22023';
  end if;

  select * into v_p from public.payments p where p.gateway = p_gateway and p.reference = p_reference;
  if found then
    if v_p.customer_id <> p_customer_id
       or v_p.booking_id is distinct from (case when p_kind = 'booking' then p_target_id end)
       or v_p.service_order_id is distinct from (case when p_kind = 'service_order' then p_target_id end) then
      raise exception 'reference_already_used' using errcode = '23505';
    end if;
    return query select v_p.id, v_p.amount_minor, v_p.currency;
    return;
  end if;

  if p_kind = 'booking' then
    select * into v_b from public.bookings b where b.id = p_target_id for update;
    if not found or v_b.customer_id <> p_customer_id then
      raise exception 'booking_not_found' using errcode = 'P0002';
    end if;
    if v_b.status <> 'pending_payment' or v_b.payment_expires_at <= now() then
      raise exception 'booking_not_payable' using errcode = '23514';
    end if;
    insert into public.payments (booking_id, customer_id, gateway, reference, amount_minor, currency)
    values (v_b.id, v_b.customer_id, p_gateway, p_reference, v_b.price_minor, v_b.currency)
    returning * into v_p;
  else
    select * into v_o from public.service_orders o where o.id = p_target_id for update;
    if not found or v_o.customer_id <> p_customer_id then
      raise exception 'order_not_found' using errcode = 'P0002';
    end if;
    if v_o.status <> 'pending_payment' or v_o.payment_expires_at <= now() then
      raise exception 'order_not_payable' using errcode = '23514';
    end if;
    insert into public.payments (service_order_id, customer_id, gateway, reference, amount_minor, currency)
    values (v_o.id, v_o.customer_id, p_gateway, p_reference, v_o.price_minor, v_o.currency)
    returning * into v_p;
  end if;

  return query select v_p.id, v_p.amount_minor, v_p.currency;
end;
$$;

-- Webhook inbox. Returns true when the event is new and should be processed,
-- false when it is a replay that has already been seen.
create function public.record_payment_event(
  p_gateway text,
  p_event_id text,
  p_event_type text,
  p_payload jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.payment_events (gateway, event_id, event_type, signature_verified, payload)
  values (p_gateway, p_event_id, p_event_type, true, p_payload)
  on conflict (gateway, event_id) do nothing
  returning id into v_id;
  return v_id is not null;
end;
$$;

create function public.finish_payment_event(p_gateway text, p_event_id text, p_result text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.payment_events
     set processed_at = now(), processing_result = left(p_result, 200)
   where gateway = p_gateway and event_id = p_event_id;
$$;

-- Step 2: the gateway says the payment succeeded. The server calls this ONLY
-- after (a) verifying the webhook signature and (b) confirming the transaction
-- with the gateway. The amount and currency are checked here against the item's
-- own price. Returns a status code:
--   confirmed                           booking confirmed / order marked paid
--   already_processed                   replay; nothing changed
--   unknown_reference                   no such payment; nothing changed
--   amount_mismatch                     amount/currency differ; nothing changed, investigate
--   duplicate_payment_refund_pending    the item was already paid; this one will be refunded
--   booking_unavailable_refund_pending  the booking/order expired, was cancelled or lost its
--                                       slot; a refund is queued
create function public.record_payment_success(
  p_gateway text,
  p_reference text,
  p_gateway_transaction_id text,
  p_amount_minor bigint,
  p_currency text,
  p_paid_at timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.payments%rowtype;
  v_kind text;
  v_target uuid;
  v_provider uuid;
  v_fee bigint;
  v_price bigint;
  v_payable boolean;
  v_duplicate boolean;
begin
  select * into v_pay
    from public.payments p
   where p.gateway = p_gateway and p.reference = p_reference
   for update;
  if not found then
    return 'unknown_reference';
  end if;
  if v_pay.status = 'succeeded' then
    return 'already_processed';
  end if;
  if p_amount_minor is distinct from v_pay.amount_minor or p_currency is distinct from v_pay.currency then
    return 'amount_mismatch';
  end if;
  if p_gateway_transaction_id is null or btrim(p_gateway_transaction_id) = '' then
    raise exception 'missing_gateway_transaction_id' using errcode = '22023';
  end if;

  -- Lock the item being paid for, so two payments for it cannot race.
  if v_pay.booking_id is not null then
    v_kind := 'booking';
    v_target := v_pay.booking_id;
    select b.provider_id, b.platform_fee_minor, b.price_minor, b.status = 'pending_payment'
      into v_provider, v_fee, v_price, v_payable
      from public.bookings b where b.id = v_target for update;
  else
    v_kind := 'service_order';
    v_target := v_pay.service_order_id;
    select o.provider_id, o.platform_fee_minor, o.price_minor, o.status = 'pending_payment'
      into v_provider, v_fee, v_price, v_payable
      from public.service_orders o where o.id = v_target for update;
  end if;

  select exists (
    select 1 from public.payments o
     where o.status = 'succeeded' and o.id <> v_pay.id
       and o.booking_id is not distinct from v_pay.booking_id
       and o.service_order_id is not distinct from v_pay.service_order_id
  ) into v_duplicate;

  update public.payments
     set status = 'succeeded',
         gateway_transaction_id = p_gateway_transaction_id,
         paid_at = coalesce(p_paid_at, now()),
         failure_reason = null
   where id = v_pay.id;

  -- The money has really arrived, so it is recorded no matter what happens next.
  perform private.post_ledger(
    'payment_captured', 'capture:' || v_pay.id, v_kind, v_target, v_pay.id, null, null,
    jsonb_build_array(
      jsonb_build_object('account', 'gateway_clearing', 'direction', 'debit', 'amount_minor', v_pay.amount_minor),
      jsonb_build_object('account', 'held_funds', 'direction', 'credit', 'amount_minor', v_pay.amount_minor)
    )
  );

  if v_duplicate then
    perform private.queue_refund(v_pay.id, 'duplicate_payment', 'duplicate:' || v_pay.id);
    return 'duplicate_payment_refund_pending';
  end if;

  if v_payable then
    begin
      if v_kind = 'booking' then
        update public.bookings set status = 'confirmed' where id = v_target;
      else
        update public.service_orders set status = 'paid' where id = v_target;
      end if;
    exception when exclusion_violation then
      -- The unpaid hold had timed out and someone else took the slot meanwhile.
      v_payable := false;
    end;
  end if;

  if not v_payable then
    perform private.queue_refund(v_pay.id, 'booking_unavailable', 'unavailable:' || v_pay.id);
    return 'booking_unavailable_refund_pending';
  end if;

  insert into public.provider_earnings (provider_id, source_kind, source_id, gross_minor, fee_minor, net_minor)
  values (v_provider, v_kind, v_target, v_price, v_fee, v_price - v_fee)
  on conflict (source_kind, source_id) do nothing;

  return 'confirmed';
end;
$$;

-- The gateway says the payment failed or was abandoned.
create function public.record_payment_failure(p_gateway text, p_reference text, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.payments%rowtype;
begin
  select * into v_pay from public.payments p
   where p.gateway = p_gateway and p.reference = p_reference for update;
  if not found then
    return 'unknown_reference';
  end if;
  if v_pay.status <> 'initialized' then
    return 'ignored_' || v_pay.status;
  end if;
  update public.payments set status = 'failed', failure_reason = left(p_reason, 300) where id = v_pay.id;
  return 'failed';
end;
$$;

-- The server reports the outcome of a refund it sent to the gateway.
create function public.record_refund_result(
  p_refund_id uuid,
  p_status text,
  p_gateway_refund_id text default null,
  p_failure_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r public.refunds%rowtype;
  v_kind text;
  v_target uuid;
begin
  if p_status not in ('succeeded', 'failed') then
    raise exception 'invalid_refund_status' using errcode = '22023';
  end if;

  select * into v_r from public.refunds r where r.id = p_refund_id for update;
  if not found then
    raise exception 'refund_not_found' using errcode = 'P0002';
  end if;
  if v_r.status <> 'pending' then
    return 'already_' || v_r.status;
  end if;

  if p_status = 'failed' then
    update public.refunds
       set status = 'failed', failure_reason = left(p_failure_reason, 300), processed_at = now()
     where id = v_r.id;
    return 'failed';
  end if;

  v_kind := case when v_r.booking_id is not null then 'booking' else 'service_order' end;
  v_target := coalesce(v_r.booking_id, v_r.service_order_id);

  if private.held_balance(v_kind, v_target) < v_r.amount_minor then
    raise exception 'held_funds_insufficient' using errcode = '23514';
  end if;

  perform private.post_ledger(
    'refund_issued', 'refund:' || v_r.id, v_kind, v_target, v_r.payment_id, v_r.id, null,
    jsonb_build_array(
      jsonb_build_object('account', 'held_funds', 'direction', 'debit', 'amount_minor', v_r.amount_minor),
      jsonb_build_object('account', 'gateway_clearing', 'direction', 'credit', 'amount_minor', v_r.amount_minor)
    )
  );

  update public.refunds
     set status = 'succeeded', gateway_refund_id = p_gateway_refund_id, processed_at = now()
   where id = v_r.id;

  -- A refund that undoes the sale means the provider earns nothing from it. A
  -- refund of a duplicate or unavailable payment does not touch the real sale.
  if v_r.reason not in ('duplicate_payment', 'booking_unavailable') then
    update public.provider_earnings
       set status = 'void'
     where source_kind = v_kind and source_id = v_target and status in ('pending', 'disputed');
  end if;

  -- Only now, with the refund confirmed by the gateway, is the item "refunded".
  if v_kind = 'booking' then
    update public.bookings set status = 'refunded' where id = v_target and status = 'cancelled';
  else
    update public.service_orders set status = 'refunded' where id = v_target and status = 'cancelled';
  end if;

  return 'succeeded';
end;
$$;

-- After a failed refund the server can try again. The new request gets its own
-- key; the combined refunds can never exceed the payment.
create function public.requeue_failed_refund(p_refund_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r public.refunds%rowtype;
begin
  select * into v_r from public.refunds r where r.id = p_refund_id;
  if not found or v_r.status <> 'failed' then
    raise exception 'refund_not_failed' using errcode = '23514';
  end if;
  return private.queue_refund(v_r.payment_id, v_r.reason,
    'retry:' || v_r.id || ':' || (select count(*) from public.refunds x where x.payment_id = v_r.payment_id));
end;
$$;

-- Server functions: paid conversation sessions -----------------------------------

-- The server starts a session when a participant joins at the right time.
create function public.start_booking_session(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b public.bookings%rowtype;
begin
  select * into v_b from public.bookings b where b.id = p_booking_id for update;
  if not found then
    raise exception 'booking_not_found' using errcode = 'P0002';
  end if;
  if v_b.status = 'in_progress' then
    return 'already_in_progress';
  end if;
  if v_b.status <> 'confirmed' then
    raise exception 'booking_not_startable' using errcode = '23514';
  end if;
  if now() < v_b.starts_at - interval '10 minutes' or now() > v_b.ends_at then
    raise exception 'outside_session_window' using errcode = '23514';
  end if;
  update public.bookings set status = 'in_progress' where id = v_b.id;
  return 'in_progress';
end;
$$;

-- The server completes a session; the earnings hold window starts.
create function public.complete_booking(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b public.bookings%rowtype;
begin
  select * into v_b from public.bookings b where b.id = p_booking_id for update;
  if not found then
    raise exception 'booking_not_found' using errcode = 'P0002';
  end if;
  if v_b.status = 'completed' then
    return 'already_completed';
  end if;
  if v_b.status <> 'in_progress' then
    raise exception 'booking_not_completable' using errcode = '23514';
  end if;
  update public.bookings set status = 'completed' where id = v_b.id;
  perform private.queue_release('booking', v_b.id, 'completed');
  return 'completed';
end;
$$;

-- Run on a schedule: sessions that were started and whose time is over are
-- completed, and confirmed sessions that nobody started are cancelled and
-- refunded in full. (No-show rules are a product decision: see docs/payments.md.)
create function public.settle_sessions()
returns table (completed_count integer, missed_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b public.bookings%rowtype;
  v_pay_id uuid;
  v_done integer := 0;
  v_missed integer := 0;
begin
  for v_b in
    select * from public.bookings b
     where b.status = 'in_progress' and b.ends_at < now() - interval '10 minutes'
     for update skip locked
  loop
    update public.bookings set status = 'completed' where id = v_b.id;
    perform private.queue_release('booking', v_b.id, 'completed');
    v_done := v_done + 1;
  end loop;

  for v_b in
    select * from public.bookings b
     where b.status = 'confirmed' and b.ends_at < now() - interval '15 minutes'
     for update skip locked
  loop
    select p.id into v_pay_id from public.payments p
     where p.booking_id = v_b.id and p.status = 'succeeded'
     order by p.paid_at asc limit 1;

    update public.bookings
       set status = 'cancelled', cancelled_by_role = 'system', cancel_reason = 'session_not_held'
     where id = v_b.id;

    if v_pay_id is not null then
      perform private.queue_refund(v_pay_id, 'session_not_held', 'missed:' || v_b.id);
    end if;
    v_missed := v_missed + 1;
  end loop;

  return query select v_done, v_missed;
end;
$$;

-- A participant cancels a booking. All amounts and rules are decided here:
--   * unpaid booking: cancelled, nothing to refund.
--   * paid, cancelled by the provider: full refund, always.
--   * paid, cancelled by the customer at least free_cancellation_hours before the
--     start: full refund.
--   * paid, cancelled by the customer later than that: no refund, and the
--     provider is paid as usual (after the normal hold).
--   * a session already in progress cannot be cancelled by either person.
-- The booking becomes "cancelled" now; it only becomes "refunded" after the
-- gateway confirms the refund.
create function public.cancel_booking(p_booking_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_b public.bookings%rowtype;
  v_role text;
  v_pay public.payments%rowtype;
  v_hours integer;
  v_refund_id uuid;
  v_refund_minor bigint := 0;
  v_late boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_reason is not null and char_length(p_reason) > 500 then
    raise exception 'reason_too_long' using errcode = '22001';
  end if;

  select * into v_b from public.bookings b where b.id = p_booking_id for update;
  if not found or (v_b.customer_id <> v_uid and v_b.provider_id <> v_uid)
     or (v_b.provider_id = v_uid and v_b.confirmed_at is null) then
    raise exception 'booking_not_found' using errcode = 'P0002';
  end if;
  v_role := case when v_uid = v_b.customer_id then 'customer' else 'provider' end;

  if v_b.status = 'pending_payment' then
    if v_role <> 'customer' then
      raise exception 'booking_not_found' using errcode = 'P0002';
    end if;
    update public.bookings
       set status = 'cancelled', cancelled_by = v_uid, cancelled_by_role = v_role, cancel_reason = p_reason
     where id = v_b.id;
    update public.payments set status = 'cancelled' where booking_id = v_b.id and status = 'initialized';
    return jsonb_build_object('status', 'cancelled', 'refund_minor', 0, 'refund_id', null);
  end if;

  if v_b.status <> 'confirmed' then
    raise exception 'booking_cannot_be_cancelled' using errcode = '23514';
  end if;

  select * into v_pay from public.payments p
   where p.booking_id = v_b.id and p.status = 'succeeded'
   order by p.paid_at asc limit 1;
  if not found then
    raise exception 'payment_missing' using errcode = '23514';
  end if;

  select s.free_cancellation_hours into v_hours from public.platform_settings s;
  v_late := v_role = 'customer' and v_b.starts_at - now() < v_hours * interval '1 hour';

  update public.bookings
     set status = 'cancelled', cancelled_by = v_uid, cancelled_by_role = v_role, cancel_reason = p_reason
   where id = v_b.id;

  if v_late then
    perform private.queue_release('booking', v_b.id, 'late_cancellation');
  else
    v_refund_minor := v_pay.amount_minor;
    v_refund_id := private.queue_refund(
      v_pay.id,
      case when v_role = 'provider' then 'cancelled_by_provider' else 'cancelled_by_customer' end,
      'cancel:' || v_b.id);
  end if;

  return jsonb_build_object('status', 'cancelled', 'refund_minor', v_refund_minor, 'refund_id', v_refund_id);
end;
$$;

-- The customer disputes a finished session while the provider's earnings are
-- still on hold. The earnings freeze until an administrator decides.
create function public.raise_booking_dispute(p_booking_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_b public.bookings%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_frozen integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_reason is null or char_length(v_reason) > 1000 then
    raise exception 'invalid_reason' using errcode = '22023';
  end if;

  select * into v_b from public.bookings b where b.id = p_booking_id for update;
  if not found or v_b.customer_id <> v_uid then
    raise exception 'booking_not_found' using errcode = 'P0002';
  end if;
  if v_b.status = 'disputed' then
    return 'already_disputed';
  end if;
  if v_b.status <> 'completed' then
    raise exception 'booking_cannot_be_disputed' using errcode = '23514';
  end if;

  update public.provider_earnings
     set status = 'disputed'
   where source_kind = 'booking' and source_id = v_b.id and status = 'pending';
  get diagnostics v_frozen = row_count;
  if v_frozen = 0 then
    -- The hold window has passed and the money was already released.
    raise exception 'dispute_window_closed' using errcode = '23514';
  end if;

  update public.bookings set status = 'disputed', dispute_reason = v_reason where id = v_b.id;
  return 'disputed';
end;
$$;

-- Server functions: paid services --------------------------------------------------

-- The provider starts work on a paid order.
create function public.start_service_order(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_o public.service_orders%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_o from public.service_orders o where o.id = p_order_id for update;
  if not found or v_o.provider_id <> v_uid or v_o.paid_at is null then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_o.status = 'in_progress' then
    return 'already_in_progress';
  end if;
  if v_o.status <> 'paid' then
    raise exception 'order_not_startable' using errcode = '23514';
  end if;
  update public.service_orders set status = 'in_progress' where id = v_o.id;
  return 'in_progress';
end;
$$;

-- The provider delivers. A file, if any, must already be uploaded to this
-- order's folder in the private bucket.
create function public.deliver_service_order(p_order_id uuid, p_note text, p_file_path text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_o public.service_orders%rowtype;
  v_note text := nullif(btrim(p_note), '');
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_note is null or char_length(v_note) > 2000 then
    raise exception 'invalid_note' using errcode = '22023';
  end if;

  select * into v_o from public.service_orders o where o.id = p_order_id for update;
  if not found or v_o.provider_id <> v_uid or v_o.paid_at is null then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_o.status <> 'in_progress' then
    raise exception 'order_not_deliverable' using errcode = '23514';
  end if;

  if p_file_path is not null then
    if p_file_path not like v_o.id::text || '/%'
       or not exists (select 1 from storage.objects so
                       where so.bucket_id = 'service-deliveries' and so.name = p_file_path) then
      raise exception 'delivery_file_not_found' using errcode = '22023';
    end if;
  end if;

  insert into public.service_deliveries (order_id, provider_id, note, file_path)
  values (v_o.id, v_uid, v_note, p_file_path)
  returning id into v_id;

  update public.service_orders set status = 'delivered' where id = v_o.id;
  return v_id;
end;
$$;

-- The customer accepts the delivery; the earnings hold window starts.
create function public.accept_service_delivery(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_o public.service_orders%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_o from public.service_orders o where o.id = p_order_id for update;
  if not found or v_o.customer_id <> v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_o.status = 'completed' then
    return 'already_completed';
  end if;
  if v_o.status <> 'delivered' then
    raise exception 'order_not_acceptable' using errcode = '23514';
  end if;
  update public.service_orders set status = 'completed' where id = v_o.id;
  perform private.queue_release('service_order', v_o.id, 'delivery_accepted');
  return 'completed';
end;
$$;

-- Run on a schedule: a delivery the customer never answered completes itself
-- after service_auto_release_days, unless it has been disputed.
create function public.settle_service_orders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o public.service_orders%rowtype;
  v_days integer;
  v_count integer := 0;
begin
  select s.service_auto_release_days into v_days from public.platform_settings s;
  for v_o in
    select * from public.service_orders o
     where o.status = 'delivered' and o.delivered_at <= now() - v_days * interval '1 day'
     for update skip locked
  loop
    update public.service_orders set status = 'completed' where id = v_o.id;
    perform private.queue_release('service_order', v_o.id, 'auto_released');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Cancelling an order:
--   * unpaid: the customer cancels, nothing to refund.
--   * paid and not started: either person cancels, full refund.
--   * in progress: the provider can cancel (full refund); the customer can only
--     cancel once the delivery deadline has passed (full refund).
--   * delivered or later: not cancellable; use a dispute instead.
create function public.cancel_service_order(p_order_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_o public.service_orders%rowtype;
  v_role text;
  v_pay public.payments%rowtype;
  v_refund_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_reason is not null and char_length(p_reason) > 500 then
    raise exception 'reason_too_long' using errcode = '22001';
  end if;

  select * into v_o from public.service_orders o where o.id = p_order_id for update;
  if not found or (v_o.customer_id <> v_uid and v_o.provider_id <> v_uid)
     or (v_o.provider_id = v_uid and v_o.paid_at is null) then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  v_role := case when v_uid = v_o.customer_id then 'customer' else 'provider' end;

  if v_o.status = 'pending_payment' then
    if v_role <> 'customer' then
      raise exception 'order_not_found' using errcode = 'P0002';
    end if;
    update public.service_orders
       set status = 'cancelled', cancelled_by = v_uid, cancelled_by_role = v_role, cancel_reason = p_reason
     where id = v_o.id;
    update public.payments set status = 'cancelled' where service_order_id = v_o.id and status = 'initialized';
    return jsonb_build_object('status', 'cancelled', 'refund_minor', 0, 'refund_id', null);
  end if;

  if v_o.status = 'in_progress' and v_role = 'customer' and now() <= v_o.due_at then
    raise exception 'order_in_progress' using errcode = '23514';
  end if;
  if v_o.status not in ('paid', 'in_progress') then
    raise exception 'order_cannot_be_cancelled' using errcode = '23514';
  end if;

  select * into v_pay from public.payments p
   where p.service_order_id = v_o.id and p.status = 'succeeded'
   order by p.paid_at asc limit 1;
  if not found then
    raise exception 'payment_missing' using errcode = '23514';
  end if;

  update public.service_orders
     set status = 'cancelled', cancelled_by = v_uid, cancelled_by_role = v_role, cancel_reason = p_reason
   where id = v_o.id;

  v_refund_id := private.queue_refund(v_pay.id, 'service_not_delivered', 'cancel-order:' || v_o.id);
  return jsonb_build_object('status', 'cancelled', 'refund_minor', v_pay.amount_minor, 'refund_id', v_refund_id);
end;
$$;

-- The customer disputes a delivered (or just completed) order while the
-- provider's earnings are still on hold.
create function public.raise_service_dispute(p_order_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_o public.service_orders%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_frozen integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_reason is null or char_length(v_reason) > 1000 then
    raise exception 'invalid_reason' using errcode = '22023';
  end if;

  select * into v_o from public.service_orders o where o.id = p_order_id for update;
  if not found or v_o.customer_id <> v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_o.status = 'disputed' then
    return 'already_disputed';
  end if;
  if v_o.status not in ('delivered', 'completed') then
    raise exception 'order_cannot_be_disputed' using errcode = '23514';
  end if;

  update public.provider_earnings
     set status = 'disputed'
   where source_kind = 'service_order' and source_id = v_o.id and status = 'pending';
  get diagnostics v_frozen = row_count;
  if v_frozen = 0 then
    raise exception 'dispute_window_closed' using errcode = '23514';
  end if;

  update public.service_orders set status = 'disputed', dispute_reason = v_reason where id = v_o.id;
  return 'disputed';
end;
$$;

-- Server functions: payouts ----------------------------------------------------------

create function public.upsert_payout_account(
  p_provider_id uuid,
  p_gateway text,
  p_recipient_code text,
  p_bank_name text,
  p_account_name text,
  p_account_last4 text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- Called by the server only after the gateway has verified the account.
  insert into public.payout_accounts
    (provider_id, gateway, recipient_code, bank_name, account_name, account_last4, verified_at)
  values
    (p_provider_id, p_gateway, p_recipient_code, p_bank_name, p_account_name, p_account_last4, now())
  on conflict (provider_id) do update
    set gateway = excluded.gateway,
        recipient_code = excluded.recipient_code,
        bank_name = excluded.bank_name,
        account_name = excluded.account_name,
        account_last4 = excluded.account_last4,
        verified_at = excluded.verified_at
  returning id into v_id;
  return v_id;
end;
$$;

-- Pays out every AVAILABLE earning of a provider in one payout. Money that is
-- still pending or disputed is never included. Calling again with the same
-- idempotency key returns the same payout.
create function public.create_payout(p_provider_id uuid, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing uuid;
  v_account public.payout_accounts%rowtype;
  v_min bigint;
  v_total bigint;
  v_payout uuid;
begin
  if p_idempotency_key is null or char_length(p_idempotency_key) < 8 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select p.id into v_existing from public.payouts p where p.idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_account from public.payout_accounts a
   where a.provider_id = p_provider_id and a.verified_at is not null;
  if not found then
    raise exception 'no_verified_payout_account' using errcode = '23514';
  end if;

  select s.min_payout_minor into v_min from public.platform_settings s;

  -- Lock the earnings rows so two requests cannot both claim the same money.
  select coalesce(sum(e.net_minor), 0) into v_total
    from (
      select pe.net_minor
        from public.provider_earnings pe
       where pe.provider_id = p_provider_id and pe.status = 'available'
       for update
    ) e;

  if v_total = 0 or v_total < v_min then
    raise exception 'below_minimum_payout' using errcode = '23514';
  end if;

  insert into public.payouts (provider_id, payout_account_id, amount_minor, idempotency_key, gateway)
  values (p_provider_id, v_account.id, v_total, p_idempotency_key, v_account.gateway)
  returning id into v_payout;

  update public.provider_earnings
     set status = 'in_payout', payout_id = v_payout
   where provider_id = p_provider_id and status = 'available';

  perform private.post_ledger(
    'payout_requested', 'payout_requested:' || v_payout, null, null, null, null, v_payout,
    jsonb_build_array(
      jsonb_build_object('account', 'provider_payable', 'direction', 'debit',
                         'amount_minor', v_total, 'owner_id', p_provider_id),
      jsonb_build_object('account', 'payouts_pending', 'direction', 'credit',
                         'amount_minor', v_total, 'owner_id', p_provider_id)
    )
  );
  return v_payout;
end;
$$;

create function public.mark_payout_processing(p_payout_id uuid, p_gateway_transfer_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.payouts%rowtype;
begin
  select * into v_p from public.payouts p where p.id = p_payout_id for update;
  if not found then
    raise exception 'payout_not_found' using errcode = 'P0002';
  end if;
  if v_p.status <> 'requested' then
    return 'already_' || v_p.status;
  end if;
  update public.payouts set status = 'processing', gateway_transfer_id = p_gateway_transfer_id
   where id = v_p.id;
  return 'processing';
end;
$$;

create function public.mark_payout_paid(p_payout_id uuid, p_fee_minor bigint default 0)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.payouts%rowtype;
begin
  select * into v_p from public.payouts p where p.id = p_payout_id for update;
  if not found then
    raise exception 'payout_not_found' using errcode = 'P0002';
  end if;
  if v_p.status in ('paid', 'failed') then
    return 'already_' || v_p.status;
  end if;
  if p_fee_minor is null or p_fee_minor < 0 then
    raise exception 'invalid_fee' using errcode = '22023';
  end if;

  perform private.post_ledger(
    'payout_paid', 'payout_paid:' || v_p.id, null, null, null, null, v_p.id,
    jsonb_build_array(
      jsonb_build_object('account', 'payouts_pending', 'direction', 'debit',
                         'amount_minor', v_p.amount_minor, 'owner_id', v_p.provider_id),
      jsonb_build_object('account', 'gateway_clearing', 'direction', 'credit',
                         'amount_minor', v_p.amount_minor)
    )
  );
  update public.provider_earnings set status = 'paid_out' where payout_id = v_p.id and status = 'in_payout';
  update public.payouts
     set status = 'paid', fee_minor = p_fee_minor, processed_at = now()
   where id = v_p.id;
  return 'paid';
end;
$$;

-- A failed payout returns the money to the provider's AVAILABLE earnings.
create function public.mark_payout_failed(p_payout_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.payouts%rowtype;
begin
  select * into v_p from public.payouts p where p.id = p_payout_id for update;
  if not found then
    raise exception 'payout_not_found' using errcode = 'P0002';
  end if;
  if v_p.status in ('paid', 'failed') then
    return 'already_' || v_p.status;
  end if;

  perform private.post_ledger(
    'payout_failed', 'payout_failed:' || v_p.id, null, null, null, null, v_p.id,
    jsonb_build_array(
      jsonb_build_object('account', 'payouts_pending', 'direction', 'debit',
                         'amount_minor', v_p.amount_minor, 'owner_id', v_p.provider_id),
      jsonb_build_object('account', 'provider_payable', 'direction', 'credit',
                         'amount_minor', v_p.amount_minor, 'owner_id', v_p.provider_id)
    )
  );
  update public.provider_earnings
     set status = 'available', payout_id = null
   where payout_id = v_p.id and status = 'in_payout';
  update public.payouts
     set status = 'failed', failure_reason = left(p_reason, 300), processed_at = now()
   where id = v_p.id;
  return 'failed';
end;
$$;

-- Server functions: provider subscriptions ---------------------------------------------

-- What a provider is told before subscribing. NULL columns mean subscriptions are
-- not on sale yet (the founder has not set a price).
create function public.subscription_offer()
returns table (price_minor bigint, period_days integer, currency text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.subscription_price_minor, s.subscription_period_days, s.currency
    from public.platform_settings s;
$$;

-- The gateway says a subscription payment succeeded. The server calls this only
-- after verifying the webhook signature. The amount is checked against the price
-- the platform has configured; the period only ever moves forward; and the same
-- gateway reference can be applied only once.
create function public.apply_subscription_payment(
  p_gateway text,
  p_provider_id uuid,
  p_reference text,
  p_amount_minor bigint,
  p_currency text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_customer_code text default null,
  p_subscription_code text default null,
  p_event_at timestamptz default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_price bigint;
  v_invoice uuid;
  v_sub public.provider_subscriptions%rowtype;
  v_event_at timestamptz := coalesce(p_event_at, now());
begin
  select s.subscription_price_minor into v_price from public.platform_settings s;
  if v_price is null then
    return 'subscriptions_not_on_sale';
  end if;
  if p_amount_minor is distinct from v_price or p_currency is distinct from 'NGN' then
    return 'amount_mismatch';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end <= p_period_start
     or p_period_end - p_period_start > interval '400 days' then
    return 'invalid_period';
  end if;
  if not exists (select 1 from public.provider_profiles pp where pp.user_id = p_provider_id) then
    return 'unknown_provider';
  end if;

  insert into public.subscription_invoices
    (provider_id, gateway, reference, amount_minor, currency, period_start, period_end)
  values (p_provider_id, p_gateway, p_reference, p_amount_minor, p_currency, p_period_start, p_period_end)
  on conflict (gateway, reference) do nothing
  returning id into v_invoice;

  if v_invoice is null then
    return 'already_processed';
  end if;

  -- The money has arrived, so it is recorded whatever happens to the entitlement.
  perform private.post_ledger(
    'subscription_payment', 'subscription:' || v_invoice, 'subscription', v_invoice, null, null, null,
    jsonb_build_array(
      jsonb_build_object('account', 'gateway_clearing', 'direction', 'debit', 'amount_minor', p_amount_minor),
      jsonb_build_object('account', 'platform_revenue', 'direction', 'credit', 'amount_minor', p_amount_minor)
    )
  );

  select * into v_sub from public.provider_subscriptions s where s.provider_id = p_provider_id for update;
  if not found then
    insert into public.provider_subscriptions
      (provider_id, status, gateway, gateway_customer_code, gateway_subscription_code,
       current_period_start, current_period_end, last_event_at)
    values
      (p_provider_id, 'active', p_gateway, p_customer_code, p_subscription_code,
       p_period_start, p_period_end, v_event_at);
    return 'activated';
  end if;

  if v_sub.status = 'revoked' then
    -- An administrator removed this subscription; payments do not bring it back.
    return 'subscription_revoked';
  end if;

  -- Late or repeated payments for an older period never shorten the new one.
  if p_period_end > v_sub.current_period_end or v_sub.status = 'ended' then
    update public.provider_subscriptions
       set status = 'active',
           cancel_at_period_end = false,
           current_period_start = case when p_period_end > v_sub.current_period_end
                                       then p_period_start else v_sub.current_period_start end,
           current_period_end = greatest(v_sub.current_period_end, p_period_end),
           gateway_customer_code = coalesce(p_customer_code, v_sub.gateway_customer_code),
           gateway_subscription_code = coalesce(p_subscription_code, v_sub.gateway_subscription_code),
           last_event_at = greatest(v_sub.last_event_at, v_event_at)
     where provider_id = p_provider_id;
    return 'renewed';
  end if;

  update public.provider_subscriptions
     set last_event_at = greatest(last_event_at, v_event_at)
   where provider_id = p_provider_id;
  return 'recorded';
end;
$$;

-- Other subscription events from the gateway: payment_failed, cancel_requested,
-- resumed, disabled. Out-of-order delivery is handled by ignoring any event older
-- than the newest one already applied. None of them ends access early: the provider
-- keeps what they paid for until current_period_end.
create function public.apply_subscription_event(
  p_provider_id uuid,
  p_event text,
  p_event_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub public.provider_subscriptions%rowtype;
begin
  if p_event not in ('payment_failed', 'cancel_requested', 'resumed', 'disabled') then
    raise exception 'unknown_subscription_event' using errcode = '22023';
  end if;
  if p_event_at is null then
    raise exception 'event_time_required' using errcode = '22023';
  end if;

  select * into v_sub from public.provider_subscriptions s where s.provider_id = p_provider_id for update;
  if not found then
    return 'no_subscription';
  end if;
  if v_sub.status = 'revoked' then
    return 'subscription_revoked';
  end if;
  if p_event_at < v_sub.last_event_at then
    return 'stale_ignored';
  end if;

  if p_event = 'payment_failed' then
    update public.provider_subscriptions
       set status = case when status = 'active' then 'past_due' else status end,
           last_event_at = p_event_at
     where provider_id = p_provider_id;
  elsif p_event in ('cancel_requested', 'disabled') then
    update public.provider_subscriptions
       set cancel_at_period_end = true, last_event_at = p_event_at
     where provider_id = p_provider_id;
  else
    update public.provider_subscriptions
       set cancel_at_period_end = false, last_event_at = p_event_at
     where provider_id = p_provider_id and status in ('active', 'past_due');
    update public.provider_subscriptions set last_event_at = p_event_at where provider_id = p_provider_id;
  end if;
  return 'applied';
end;
$$;

-- Run on a schedule: marks subscriptions whose paid period has finished as ended.
-- (Entitlement does not depend on this job; it is for status display only.)
create function public.expire_subscriptions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.provider_subscriptions
     set status = 'ended'
   where status in ('active', 'past_due') and current_period_end <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reconciliation: totals per ledger account. Debits must always equal credits
-- overall; the server and the tests both check this.
create function public.ledger_trial_balance()
returns table (account text, debit_minor bigint, credit_minor bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select e.account,
         coalesce(sum(case when e.direction = 'debit' then e.amount_minor end), 0)::bigint,
         coalesce(sum(case when e.direction = 'credit' then e.amount_minor end), 0)::bigint
    from public.ledger_entries e
   group by e.account
   order by e.account;
$$;

-- Function privileges --------------------------------------------------------------
-- Supabase grants EXECUTE on new functions to every API role by default, so each
-- function is explicitly locked down, then granted only to who needs it.

revoke all on function public.create_payment(text, uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.record_payment_event(text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.finish_payment_event(text, text, text) from public, anon, authenticated;
revoke all on function public.record_payment_success(text, text, text, bigint, text, timestamptz) from public, anon, authenticated;
revoke all on function public.record_payment_failure(text, text, text) from public, anon, authenticated;
revoke all on function public.record_refund_result(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.requeue_failed_refund(uuid) from public, anon, authenticated;
revoke all on function public.release_due_earnings() from public, anon, authenticated;
revoke all on function public.start_booking_session(uuid) from public, anon, authenticated;
revoke all on function public.complete_booking(uuid) from public, anon, authenticated;
revoke all on function public.settle_sessions() from public, anon, authenticated;
revoke all on function public.cancel_booking(uuid, text) from public, anon, authenticated;
revoke all on function public.raise_booking_dispute(uuid, text) from public, anon, authenticated;
revoke all on function public.start_service_order(uuid) from public, anon, authenticated;
revoke all on function public.deliver_service_order(uuid, text, text) from public, anon, authenticated;
revoke all on function public.accept_service_delivery(uuid) from public, anon, authenticated;
revoke all on function public.settle_service_orders() from public, anon, authenticated;
revoke all on function public.cancel_service_order(uuid, text) from public, anon, authenticated;
revoke all on function public.raise_service_dispute(uuid, text) from public, anon, authenticated;
revoke all on function public.upsert_payout_account(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.create_payout(uuid, text) from public, anon, authenticated;
revoke all on function public.mark_payout_processing(uuid, text) from public, anon, authenticated;
revoke all on function public.mark_payout_paid(uuid, bigint) from public, anon, authenticated;
revoke all on function public.mark_payout_failed(uuid, text) from public, anon, authenticated;
revoke all on function public.subscription_offer() from public, anon, authenticated;
revoke all on function public.apply_subscription_payment(text, uuid, text, bigint, text, timestamptz, timestamptz, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.apply_subscription_event(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.expire_subscriptions() from public, anon, authenticated;
revoke all on function public.ledger_trial_balance() from public, anon, authenticated;
revoke all on function public.my_earnings_summary() from public, anon, authenticated;

-- Server only (service_role).
grant execute on function public.create_payment(text, uuid, uuid, text, text) to service_role;
grant execute on function public.record_payment_event(text, text, text, jsonb) to service_role;
grant execute on function public.finish_payment_event(text, text, text) to service_role;
grant execute on function public.record_payment_success(text, text, text, bigint, text, timestamptz) to service_role;
grant execute on function public.record_payment_failure(text, text, text) to service_role;
grant execute on function public.record_refund_result(uuid, text, text, text) to service_role;
grant execute on function public.requeue_failed_refund(uuid) to service_role;
grant execute on function public.release_due_earnings() to service_role;
grant execute on function public.start_booking_session(uuid) to service_role;
grant execute on function public.complete_booking(uuid) to service_role;
grant execute on function public.settle_sessions() to service_role;
grant execute on function public.settle_service_orders() to service_role;
grant execute on function public.upsert_payout_account(uuid, text, text, text, text, text) to service_role;
grant execute on function public.create_payout(uuid, text) to service_role;
grant execute on function public.mark_payout_processing(uuid, text) to service_role;
grant execute on function public.mark_payout_paid(uuid, bigint) to service_role;
grant execute on function public.mark_payout_failed(uuid, text) to service_role;
grant execute on function public.apply_subscription_payment(text, uuid, text, bigint, text, timestamptz, timestamptz, text, text, timestamptz) to service_role;
grant execute on function public.apply_subscription_event(uuid, text, timestamptz) to service_role;
grant execute on function public.expire_subscriptions() to service_role;
grant execute on function public.ledger_trial_balance() to service_role;

-- Callable by the signed-in person; each function checks who they are and what
-- they may do, and works out every amount itself.
grant execute on function public.cancel_booking(uuid, text) to authenticated, service_role;
grant execute on function public.raise_booking_dispute(uuid, text) to authenticated, service_role;
grant execute on function public.start_service_order(uuid) to authenticated, service_role;
grant execute on function public.deliver_service_order(uuid, text, text) to authenticated, service_role;
grant execute on function public.accept_service_delivery(uuid) to authenticated, service_role;
grant execute on function public.cancel_service_order(uuid, text) to authenticated, service_role;
grant execute on function public.raise_service_dispute(uuid, text) to authenticated, service_role;
grant execute on function public.my_earnings_summary() to authenticated, service_role;
grant execute on function public.subscription_offer() to authenticated, service_role;
