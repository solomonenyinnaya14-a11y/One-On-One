-- One On One migration 06: paid-conversation bookings.
--
-- A booking is one scheduled paid conversation between a customer and a provider.
-- It is a different record from the free conversation between the same two
-- people (migration 05): a paid booking never replaces, copies or deletes chat
-- history; it only links to the conversation and shows up in it as a card.
--
-- Design rules:
--   * The client NEVER supplies a price, fee, provider permission or status.
--     create_booking(offering, start time) derives everything from the database.
--   * Terms (price, fee, duration, times) are copied onto the booking when it is
--     created and can never change afterwards, even if the offering is edited or
--     the provider's subscription lapses.
--   * No API role can insert, update or delete bookings directly. Customers and
--     providers can only READ their own. Every change goes through a function
--     (migration 08 holds the ones that move money).
--   * Status changes follow a fixed state machine enforced by a trigger, so even
--     a bug in server code cannot skip a step.
--
-- State machine
--   pending_payment -> confirmed | cancelled | expired
--   confirmed       -> in_progress | cancelled
--   in_progress     -> completed | cancelled
--   completed       -> disputed          (only while earnings are still on hold)
--   disputed        -> completed | cancelled      (decided by an administrator)
--   cancelled       -> refunded          (only after the gateway confirms the refund)
--   expired and refunded are final.

set search_path = public, extensions;

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete restrict,
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  offering_id uuid not null references public.offerings (id) on delete restrict,
  -- The chat these two people share; set when the booking is confirmed.
  conversation_id uuid references public.conversations (id) on delete restrict,

  -- Terms copied from the offering and platform settings at booking time.
  kind text not null,
  title text not null,
  duration_minutes integer not null,
  price_minor bigint not null,
  currency text not null default 'NGN',
  platform_fee_bps integer not null,
  platform_fee_minor bigint not null,
  provider_earnings_minor bigint not null,

  starts_at timestamptz not null,
  ends_at timestamptz not null,

  status text not null default 'pending_payment',
  payment_expires_at timestamptz,
  confirmed_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles (id) on delete set null,
  cancelled_by_role text,
  cancel_reason text,
  disputed_at timestamptz,
  dispute_reason text,
  refunded_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint bookings_parties_differ check (customer_id <> provider_id),
  constraint bookings_kind_valid check (kind in ('text', 'voice')),
  constraint bookings_duration_valid check (duration_minutes between 10 and 120 and duration_minutes % 5 = 0),
  constraint bookings_price_valid check (price_minor between 100 and 100000000),
  constraint bookings_currency_valid check (currency = 'NGN'),
  constraint bookings_fee_bps_valid check (platform_fee_bps between 0 and 5000),
  constraint bookings_fee_valid check (platform_fee_minor between 0 and price_minor),
  constraint bookings_earnings_valid check (provider_earnings_minor = price_minor - platform_fee_minor),
  constraint bookings_times_valid
    check (ends_at = starts_at + duration_minutes * interval '1 minute'),
  constraint bookings_status_valid
    check (status in ('pending_payment', 'confirmed', 'in_progress', 'completed',
                      'disputed', 'cancelled', 'refunded', 'expired')),
  constraint bookings_hold_has_expiry
    check (status <> 'pending_payment' or payment_expires_at is not null),
  constraint bookings_confirmed_has_time
    check (status not in ('confirmed', 'in_progress', 'completed', 'disputed')
           or (confirmed_at is not null and conversation_id is not null)),
  constraint bookings_started_has_time
    check (status not in ('in_progress', 'completed', 'disputed') or started_at is not null),
  constraint bookings_completed_has_time
    check (status not in ('completed', 'disputed') or ended_at is not null),
  constraint bookings_cancelled_has_details
    check (status not in ('cancelled', 'refunded')
           or (cancelled_at is not null and cancelled_by_role is not null)),
  constraint bookings_refunded_has_time check (status <> 'refunded' or refunded_at is not null),
  constraint bookings_disputed_has_time check (status <> 'disputed' or disputed_at is not null),
  constraint bookings_cancelled_role_valid
    check (cancelled_by_role is null or cancelled_by_role in ('customer', 'provider', 'admin', 'system')),
  constraint bookings_cancel_reason_length
    check (cancel_reason is null or char_length(cancel_reason) <= 500),
  constraint bookings_dispute_reason_length
    check (dispute_reason is null or char_length(dispute_reason) <= 1000),

  -- A provider cannot be double-booked, and neither can a customer. Only live
  -- bookings count; expired, cancelled and finished ones free the time.
  constraint bookings_no_provider_overlap
    exclude using gist (
      provider_id with =,
      tstzrange(starts_at, ends_at, '[)') with &&
    ) where (status in ('pending_payment', 'confirmed', 'in_progress')),
  constraint bookings_no_customer_overlap
    exclude using gist (
      customer_id with =,
      tstzrange(starts_at, ends_at, '[)') with &&
    ) where (status in ('pending_payment', 'confirmed', 'in_progress'))
);

create index bookings_customer_idx on public.bookings (customer_id, starts_at desc);
create index bookings_provider_idx on public.bookings (provider_id, starts_at desc);
create index bookings_offering_idx on public.bookings (offering_id);
create index bookings_conversation_idx on public.bookings (conversation_id) where conversation_id is not null;
-- Lets the expiry job find unpaid holds quickly.
create index bookings_hold_expiry_idx on public.bookings (payment_expires_at)
  where status = 'pending_payment';
-- Lets the missed-session job find confirmed bookings whose time has passed.
create index bookings_confirmed_end_idx on public.bookings (ends_at)
  where status = 'confirmed';

create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function private.set_updated_at();

-- New bookings always start as an unpaid hold.
create function private.guard_booking_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status <> 'pending_payment' then
    raise exception 'booking_must_start_pending_payment' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger bookings_guard_insert
  before insert on public.bookings
  for each row execute function private.guard_booking_insert();

-- Terms are frozen, the state machine is enforced, and timestamps are stamped by
-- the database instead of being trusted from the caller.
create function private.guard_booking_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('expired', 'refunded') then
    raise exception 'booking_is_final' using errcode = '42501';
  end if;

  if (new.customer_id, new.provider_id, new.offering_id, new.kind, new.title,
      new.duration_minutes, new.price_minor, new.currency, new.platform_fee_bps,
      new.platform_fee_minor, new.provider_earnings_minor, new.starts_at,
      new.ends_at, new.created_at)
     is distinct from
     (old.customer_id, old.provider_id, old.offering_id, old.kind, old.title,
      old.duration_minutes, old.price_minor, old.currency, old.platform_fee_bps,
      old.platform_fee_minor, old.provider_earnings_minor, old.starts_at,
      old.ends_at, old.created_at)
  then
    raise exception 'booking_terms_are_immutable' using errcode = '42501';
  end if;

  -- The chat link can be set once and never moved.
  if old.conversation_id is not null and new.conversation_id is distinct from old.conversation_id then
    raise exception 'booking_conversation_is_immutable' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending_payment' and new.status in ('confirmed', 'cancelled', 'expired'))
      or (old.status = 'confirmed' and new.status in ('in_progress', 'cancelled'))
      or (old.status = 'in_progress' and new.status in ('completed', 'cancelled'))
      or (old.status = 'completed' and new.status = 'disputed')
      or (old.status = 'disputed' and new.status in ('completed', 'cancelled'))
      or (old.status = 'cancelled' and new.status = 'refunded')
    ) then
      raise exception 'invalid_booking_transition: % -> %', old.status, new.status
        using errcode = '23514';
    end if;

    if new.status = 'confirmed' then
      new.confirmed_at := now();
      new.conversation_id := private.ensure_active_conversation(new.customer_id, new.provider_id);
    elsif new.status = 'in_progress' then
      new.started_at := now();
    elsif new.status = 'completed' and old.status = 'in_progress' then
      new.ended_at := now();
    elsif new.status = 'cancelled' then
      new.cancelled_at := now();
    elsif new.status = 'disputed' then
      new.disputed_at := now();
    elsif new.status = 'refunded' then
      new.refunded_at := now();
    end if;
  end if;

  return new;
end;
$$;

create trigger bookings_guard_update
  before update on public.bookings
  for each row execute function private.guard_booking_update();

-- Booking history is financial history: it is never deleted.
create trigger bookings_forbid_delete
  before delete on public.bookings
  for each row execute function private.forbid_delete();

-- A confirmed booking appears in the chat as a card that points at the booking.
alter table public.messages
  add constraint messages_booking_fk
  foreign key (booking_id) references public.bookings (id) on delete restrict;
create index messages_booking_idx on public.messages (booking_id) where booking_id is not null;

create function private.post_booking_card()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.messages (conversation_id, kind, booking_id)
  values (new.conversation_id, 'booking_card', new.id);
  return null;
end;
$$;

create trigger bookings_post_card
  after update of status on public.bookings
  for each row
  when (new.status = 'confirmed' and old.status is distinct from 'confirmed')
  execute function private.post_booking_card();

alter table public.bookings enable row level security;
revoke all on public.bookings from anon, authenticated;
grant select on public.bookings to authenticated;

-- Customers see everything about their own bookings. Providers see a booking only
-- once it has been paid and confirmed: an unpaid hold never reveals who is
-- considering booking them.
create policy bookings_select_customer on public.bookings
  for select to authenticated
  using (customer_id = (select auth.uid()));

create policy bookings_select_provider on public.bookings
  for select to authenticated
  using (provider_id = (select auth.uid()) and confirmed_at is not null);

create policy bookings_select_admin on public.bookings
  for select to authenticated
  using ((select private.is_admin()));

-- Availability ---------------------------------------------------------------

-- True when a provider can take a session from p_starts to p_ends:
--   * the whole session sits inside one weekly availability window, measured in
--     the provider's own timezone and on a single calendar day;
--   * it does not overlap a time-off block;
--   * it does not overlap another live booking (unpaid holds that have timed out
--     do not count).
create function private.slot_is_open(p_provider uuid, p_starts timestamptz, p_ends timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1
      from public.availability_rules r
      join public.profiles p on p.id = r.provider_id
      where r.provider_id = p_provider
        and r.weekday = extract(dow from (p_starts at time zone p.timezone))::int
        and (p_starts at time zone p.timezone)::date = (p_ends at time zone p.timezone)::date
        and (p_starts at time zone p.timezone)::time >= r.start_time
        and (p_ends at time zone p.timezone)::time <= r.end_time
    )
    and not exists (
      select 1
      from public.availability_blocks b
      where b.provider_id = p_provider
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts, p_ends, '[)')
    )
    and not exists (
      select 1
      from public.bookings bk
      where bk.provider_id = p_provider
        and bk.status in ('pending_payment', 'confirmed', 'in_progress')
        and not (bk.status = 'pending_payment' and bk.payment_expires_at <= now())
        and tstzrange(bk.starts_at, bk.ends_at, '[)') && tstzrange(p_starts, p_ends, '[)')
    );
$$;

-- Open start times for an offering, every 15 minutes. Returns only times, never
-- who booked or why a time is unavailable. Public, so people can browse before
-- signing in. Returns nothing for an offering that cannot take a new booking.
create function public.get_open_slots(p_offering_id uuid, p_from timestamptz, p_to timestamptz)
returns table (slot_starts_at timestamptz, slot_ends_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_off public.offerings%rowtype;
  v_lead integer;
  v_from timestamptz;
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return;
  end if;
  if p_to - p_from > interval '14 days' then
    raise exception 'range_too_large' using errcode = '22023';
  end if;

  select * into v_off from public.offerings o where o.id = p_offering_id;
  if not found or not private.offering_accepts_bookings(v_off.id) then
    return;
  end if;

  select s.min_booking_lead_minutes into v_lead from public.platform_settings s;
  v_from := greatest(p_from, now() + v_lead * interval '1 minute');

  return query
    select g.t, g.t + v_off.duration_minutes * interval '1 minute'
    from generate_series(
           to_timestamp(ceil(extract(epoch from v_from) / 900) * 900),
           p_to - v_off.duration_minutes * interval '1 minute',
           interval '15 minutes'
         ) as g(t)
    where private.slot_is_open(v_off.provider_id, g.t, g.t + v_off.duration_minutes * interval '1 minute')
    order by g.t;
end;
$$;

revoke all on function public.get_open_slots(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.get_open_slots(uuid, timestamptz, timestamptz)
  to anon, authenticated, service_role;

-- Creating a booking -----------------------------------------------------------

-- The only way a customer creates a booking. Takes an offering and a start time
-- and works out everything else itself. Error messages are stable codes the app
-- can translate; none of them reveal private information (a block, for example,
-- is reported as generic "booking_not_allowed").
create function public.create_booking(p_offering_id uuid, p_starts_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_off public.offerings%rowtype;
  v_set public.platform_settings%rowtype;
  v_ends timestamptz;
  v_fee bigint;
  v_id uuid;
  v_constraint text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;

  -- The offering must be bookable RIGHT NOW: active, provider approved and not
  -- suspended, and either the free allowance or covered by an active
  -- subscription. A stale page or a direct API call cannot get around this.
  select * into v_off from public.offerings o where o.id = p_offering_id;
  if not found or not private.offering_accepts_bookings(v_off.id) then
    raise exception 'offering_not_available' using errcode = 'P0002';
  end if;

  if v_off.provider_id = v_uid then
    raise exception 'cannot_book_yourself' using errcode = '42501';
  end if;
  if private.is_blocked_between(v_uid, v_off.provider_id) then
    raise exception 'booking_not_allowed' using errcode = '42501';
  end if;

  select * into v_set from public.platform_settings;

  if p_starts_at is null
     or extract(second from p_starts_at) <> 0
     or (extract(minute from p_starts_at at time zone 'UTC')::int % 15) <> 0 then
    raise exception 'invalid_start_time' using errcode = '22023';
  end if;
  if p_starts_at < now() + v_set.min_booking_lead_minutes * interval '1 minute' then
    raise exception 'too_soon' using errcode = '22023';
  end if;
  if p_starts_at > now() + interval '60 days' then
    raise exception 'too_far_ahead' using errcode = '22023';
  end if;

  -- Free any unpaid holds that have timed out before checking the slot.
  update public.bookings
     set status = 'expired'
   where status = 'pending_payment'
     and payment_expires_at <= now()
     and (provider_id = v_off.provider_id or customer_id = v_uid);

  -- Stops one account from reserving many slots it never intends to pay for.
  if (select count(*) from public.bookings b
       where b.customer_id = v_uid and b.status = 'pending_payment') >= 3 then
    raise exception 'too_many_unpaid_bookings' using errcode = '54000';
  end if;

  v_ends := p_starts_at + v_off.duration_minutes * interval '1 minute';

  if not private.slot_is_open(v_off.provider_id, p_starts_at, v_ends) then
    raise exception 'slot_unavailable' using errcode = '23P01';
  end if;

  -- Fee in whole kobo, rounded down (the provider gets the remainder).
  v_fee := (v_off.price_minor * v_set.platform_fee_bps) / 10000;

  begin
    insert into public.bookings (
      customer_id, provider_id, offering_id, kind, title, duration_minutes,
      price_minor, currency, platform_fee_bps, platform_fee_minor,
      provider_earnings_minor, starts_at, ends_at, payment_expires_at
    ) values (
      v_uid, v_off.provider_id, v_off.id, v_off.kind, v_off.title, v_off.duration_minutes,
      v_off.price_minor, v_off.currency, v_set.platform_fee_bps, v_fee,
      v_off.price_minor - v_fee, p_starts_at, v_ends,
      now() + v_set.payment_window_minutes * interval '1 minute'
    )
    returning id into v_id;
  exception when exclusion_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'bookings_no_customer_overlap' then
      raise exception 'you_have_an_overlapping_booking' using errcode = '23P01';
    end if;
    raise exception 'slot_unavailable' using errcode = '23P01';
  end;

  return v_id;
end;
$$;

revoke all on function public.create_booking(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.create_booking(uuid, timestamptz) to authenticated, service_role;

-- Run on a schedule by the server: frees slots held by bookings nobody paid for.
create function public.expire_booking_holds()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.bookings
     set status = 'expired'
   where status = 'pending_payment'
     and payment_expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.expire_booking_holds() from public, anon, authenticated;
grant execute on function public.expire_booking_holds() to service_role;
