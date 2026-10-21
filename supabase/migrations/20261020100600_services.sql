-- One On One migration 07: paid services (a separate marketplace).
--
-- A paid CONVERSATION sells access to a provider's time. A paid SERVICE sells a
-- defined task or deliverable. They are kept in separate tables with separate
-- state machines on purpose: a service order is never a booking.
--
-- Services are NOT limited by the subscription allowance: the one-free-offering
-- rule applies to paid conversations only.
--
-- Money rules mirror bookings: the customer's payment is verified by the server,
-- the provider's earnings stay PENDING until the order is complete and a hold
-- window has passed (migration 08), and a listing edit never rewrites what an
-- existing customer purchased.
--
-- Service order state machine
--   pending_payment -> paid | cancelled | expired
--   paid            -> in_progress | cancelled
--   in_progress     -> delivered | cancelled
--   delivered       -> completed | disputed
--   completed       -> disputed          (only while earnings are still on hold)
--   disputed        -> completed | cancelled      (decided by an administrator)
--   cancelled       -> refunded          (only after the gateway confirms the refund)
--   expired and refunded are final.

set search_path = public, extensions;

create table public.services (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  topic_id uuid references public.topics (id) on delete restrict,
  title text not null,
  description text,
  -- What the customer receives.
  deliverable_scope text not null,
  -- What the customer must provide before work starts (shown on the order form).
  requirements_prompt text,
  price_minor bigint not null,
  currency text not null default 'NGN',
  delivery_days integer not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint services_title_length check (char_length(btrim(title)) between 1 and 100),
  constraint services_description_length check (description is null or char_length(description) <= 2000),
  constraint services_scope_length check (char_length(btrim(deliverable_scope)) between 1 and 1000),
  constraint services_requirements_length check (requirements_prompt is null or char_length(requirements_prompt) <= 500),
  constraint services_price_valid check (price_minor between 100 and 100000000),
  constraint services_currency_valid check (currency = 'NGN'),
  constraint services_delivery_days_valid check (delivery_days between 1 and 90)
);

create index services_provider_idx on public.services (provider_id);
create index services_topic_idx on public.services (topic_id);

create trigger services_set_updated_at
  before update on public.services
  for each row execute function private.set_updated_at();

-- Listings are never deleted: orders refer to them. Deactivate instead.
create trigger services_forbid_delete
  before delete on public.services
  for each row execute function private.forbid_delete();

create function private.limit_services()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.services s where s.provider_id = new.provider_id) >= 50 then
    raise exception 'too_many_services' using errcode = '54000';
  end if;
  return new;
end;
$$;

create trigger services_limit
  before insert on public.services
  for each row execute function private.limit_services();

alter table public.services enable row level security;
revoke all on public.services from anon, authenticated;
grant select on public.services to anon, authenticated;
grant insert (provider_id, topic_id, title, description, deliverable_scope, requirements_prompt,
              price_minor, delivery_days, is_active)
  on public.services to authenticated;
grant update (topic_id, title, description, deliverable_scope, requirements_prompt,
              price_minor, delivery_days, is_active)
  on public.services to authenticated;

create policy services_select_public on public.services
  for select to anon, authenticated
  using (is_active and private.is_public_provider(provider_id));

create policy services_select_own on public.services
  for select to authenticated
  using (provider_id = (select auth.uid()));

create policy services_insert_own on public.services
  for insert to authenticated
  with check (
    provider_id = (select auth.uid())
    and exists (select 1 from public.provider_profiles pp
                 where pp.user_id = provider_id and pp.status <> 'suspended')
  );

create policy services_update_own on public.services
  for update to authenticated
  using (provider_id = (select auth.uid()))
  with check (provider_id = (select auth.uid()));

-- Service orders ---------------------------------------------------------------

create table public.service_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete restrict,
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  service_id uuid not null references public.services (id) on delete restrict,
  conversation_id uuid references public.conversations (id) on delete restrict,

  -- Terms copied from the listing and platform settings at purchase time.
  title text not null,
  description text,
  deliverable_scope text not null,
  requirements_prompt text,
  delivery_days integer not null,
  price_minor bigint not null,
  currency text not null default 'NGN',
  platform_fee_bps integer not null,
  platform_fee_minor bigint not null,
  provider_earnings_minor bigint not null,

  -- The customer's answer to requirements_prompt.
  requirements_response text,

  status text not null default 'pending_payment',
  payment_expires_at timestamptz,
  paid_at timestamptz,
  -- Set when payment is verified: paid_at + delivery_days.
  due_at timestamptz,
  started_at timestamptz,
  delivered_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles (id) on delete set null,
  cancelled_by_role text,
  cancel_reason text,
  disputed_at timestamptz,
  dispute_reason text,
  refunded_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint service_orders_parties_differ check (customer_id <> provider_id),
  constraint service_orders_title_length check (char_length(btrim(title)) between 1 and 100),
  constraint service_orders_days_valid check (delivery_days between 1 and 90),
  constraint service_orders_price_valid check (price_minor between 100 and 100000000),
  constraint service_orders_currency_valid check (currency = 'NGN'),
  constraint service_orders_fee_bps_valid check (platform_fee_bps between 0 and 5000),
  constraint service_orders_fee_valid check (platform_fee_minor between 0 and price_minor),
  constraint service_orders_earnings_valid check (provider_earnings_minor = price_minor - platform_fee_minor),
  constraint service_orders_requirements_length
    check (requirements_response is null or char_length(requirements_response) <= 4000),
  constraint service_orders_status_valid
    check (status in ('pending_payment', 'paid', 'in_progress', 'delivered', 'completed',
                      'disputed', 'cancelled', 'refunded', 'expired')),
  constraint service_orders_hold_has_expiry
    check (status <> 'pending_payment' or payment_expires_at is not null),
  constraint service_orders_paid_has_details
    check (status not in ('paid', 'in_progress', 'delivered', 'completed', 'disputed')
           or (paid_at is not null and due_at is not null and conversation_id is not null)),
  constraint service_orders_started_has_time
    check (status not in ('in_progress', 'delivered', 'completed', 'disputed') or started_at is not null),
  constraint service_orders_delivered_has_time
    check (status not in ('delivered', 'completed', 'disputed') or delivered_at is not null),
  constraint service_orders_completed_has_time check (status <> 'completed' or completed_at is not null),
  constraint service_orders_cancelled_has_details
    check (status not in ('cancelled', 'refunded')
           or (cancelled_at is not null and cancelled_by_role is not null)),
  constraint service_orders_refunded_has_time check (status <> 'refunded' or refunded_at is not null),
  constraint service_orders_disputed_has_time check (status <> 'disputed' or disputed_at is not null),
  constraint service_orders_cancelled_role_valid
    check (cancelled_by_role is null or cancelled_by_role in ('customer', 'provider', 'admin', 'system')),
  constraint service_orders_cancel_reason_length
    check (cancel_reason is null or char_length(cancel_reason) <= 500),
  constraint service_orders_dispute_reason_length
    check (dispute_reason is null or char_length(dispute_reason) <= 1000)
);

create index service_orders_customer_idx on public.service_orders (customer_id, created_at desc);
create index service_orders_provider_idx on public.service_orders (provider_id, created_at desc);
create index service_orders_service_idx on public.service_orders (service_id);
create index service_orders_hold_expiry_idx on public.service_orders (payment_expires_at)
  where status = 'pending_payment';
create index service_orders_delivered_idx on public.service_orders (delivered_at)
  where status = 'delivered';
create index service_orders_due_idx on public.service_orders (due_at)
  where status in ('paid', 'in_progress');

create trigger service_orders_set_updated_at
  before update on public.service_orders
  for each row execute function private.set_updated_at();

create function private.guard_service_order_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status <> 'pending_payment' then
    raise exception 'service_order_must_start_pending_payment' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger service_orders_guard_insert
  before insert on public.service_orders
  for each row execute function private.guard_service_order_insert();

create function private.guard_service_order_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('expired', 'refunded') then
    raise exception 'service_order_is_final' using errcode = '42501';
  end if;

  -- What the customer bought can never be rewritten.
  if (new.customer_id, new.provider_id, new.service_id, new.title, new.description,
      new.deliverable_scope, new.requirements_prompt, new.delivery_days, new.price_minor,
      new.currency, new.platform_fee_bps, new.platform_fee_minor, new.provider_earnings_minor,
      new.requirements_response, new.created_at)
     is distinct from
     (old.customer_id, old.provider_id, old.service_id, old.title, old.description,
      old.deliverable_scope, old.requirements_prompt, old.delivery_days, old.price_minor,
      old.currency, old.platform_fee_bps, old.platform_fee_minor, old.provider_earnings_minor,
      old.requirements_response, old.created_at)
  then
    raise exception 'service_order_terms_are_immutable' using errcode = '42501';
  end if;

  if old.conversation_id is not null and new.conversation_id is distinct from old.conversation_id then
    raise exception 'service_order_conversation_is_immutable' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending_payment' and new.status in ('paid', 'cancelled', 'expired'))
      or (old.status = 'paid' and new.status in ('in_progress', 'cancelled'))
      or (old.status = 'in_progress' and new.status in ('delivered', 'cancelled'))
      or (old.status = 'delivered' and new.status in ('completed', 'disputed'))
      or (old.status = 'completed' and new.status = 'disputed')
      or (old.status = 'disputed' and new.status in ('completed', 'cancelled'))
      or (old.status = 'cancelled' and new.status = 'refunded')
    ) then
      raise exception 'invalid_service_order_transition: % -> %', old.status, new.status
        using errcode = '23514';
    end if;

    if new.status = 'paid' then
      new.paid_at := now();
      new.due_at := now() + new.delivery_days * interval '1 day';
      new.conversation_id := private.ensure_active_conversation(new.customer_id, new.provider_id);
    elsif new.status = 'in_progress' then
      new.started_at := now();
    elsif new.status = 'delivered' then
      new.delivered_at := now();
    elsif new.status = 'completed' then
      new.completed_at := coalesce(old.completed_at, now());
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

create trigger service_orders_guard_update
  before update on public.service_orders
  for each row execute function private.guard_service_order_update();

create trigger service_orders_forbid_delete
  before delete on public.service_orders
  for each row execute function private.forbid_delete();

-- A paid order appears in the chat as a card that points at the order.
alter table public.messages
  add constraint messages_service_order_fk
  foreign key (service_order_id) references public.service_orders (id) on delete restrict;
create index messages_service_order_idx on public.messages (service_order_id) where service_order_id is not null;

create function private.post_service_card()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.messages (conversation_id, kind, service_order_id)
  values (new.conversation_id, 'service_card', new.id);
  return null;
end;
$$;

create trigger service_orders_post_card
  after update of status on public.service_orders
  for each row
  when (new.status = 'paid' and old.status is distinct from 'paid')
  execute function private.post_service_card();

alter table public.service_orders enable row level security;
revoke all on public.service_orders from anon, authenticated;
grant select on public.service_orders to authenticated;

create policy service_orders_select_customer on public.service_orders
  for select to authenticated
  using (customer_id = (select auth.uid()));

-- Providers see an order (and the customer's requirements) only once it is paid.
create policy service_orders_select_provider on public.service_orders
  for select to authenticated
  using (provider_id = (select auth.uid()) and paid_at is not null);

create policy service_orders_select_admin on public.service_orders
  for select to authenticated
  using ((select private.is_admin()));

-- Deliveries -------------------------------------------------------------------

create table public.service_deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.service_orders (id) on delete restrict,
  provider_id uuid not null references public.provider_profiles (user_id) on delete restrict,
  note text not null,
  -- Path inside the private service-deliveries bucket: <order_id>/<file>.
  file_path text,
  created_at timestamptz not null default now(),
  constraint service_deliveries_note_length check (char_length(btrim(note)) between 1 and 2000),
  constraint service_deliveries_path_valid
    check (file_path is null or (char_length(file_path) <= 300 and file_path like order_id::text || '/%'))
);

create index service_deliveries_order_idx on public.service_deliveries (order_id, created_at);

create trigger service_deliveries_append_only
  before update or delete on public.service_deliveries
  for each row execute function private.forbid_change();

alter table public.service_deliveries enable row level security;
revoke all on public.service_deliveries from anon, authenticated;
grant select on public.service_deliveries to authenticated;

create function private.is_service_order_party(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_orders o
    where o.id = p_order
      and (select auth.uid()) in (o.customer_id, o.provider_id)
      and o.paid_at is not null
  );
$$;

create policy service_deliveries_select_party on public.service_deliveries
  for select to authenticated
  using (private.is_service_order_party(order_id));

create policy service_deliveries_select_admin on public.service_deliveries
  for select to authenticated
  using ((select private.is_admin()));

-- Delivery files (storage) ---------------------------------------------------------
-- Private bucket: nothing is public. Files live under <order_id>/. Only the two
-- people on a paid order can read them; only the provider can upload, and only
-- while the order is open for work. Files cannot be replaced or deleted through
-- the API once uploaded.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('service-deliveries', 'service-deliveries', false, 26214400,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'application/zip',
              'text/plain',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do nothing;

create function private.can_read_delivery_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_service_order_party(private.try_uuid((storage.foldername(p_name))[1]));
$$;

create function private.can_upload_delivery_file(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.service_orders o
    where o.id = private.try_uuid((storage.foldername(p_name))[1])
      and o.provider_id = (select auth.uid())
      and o.status in ('paid', 'in_progress')
  );
$$;

create policy delivery_files_select_party on storage.objects
  for select to authenticated
  using (bucket_id = 'service-deliveries' and private.can_read_delivery_file(name));

create policy delivery_files_insert_provider on storage.objects
  for insert to authenticated
  with check (bucket_id = 'service-deliveries' and private.can_upload_delivery_file(name));

-- Buying a service ------------------------------------------------------------------

-- The only way to start an order. Takes a listing and the customer's answer and
-- works out price, fee and everything else itself.
create function public.create_service_order(p_service_id uuid, p_requirements text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_svc public.services%rowtype;
  v_set public.platform_settings%rowtype;
  v_req text := nullif(btrim(p_requirements), '');
  v_fee bigint;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;

  select * into v_svc from public.services s where s.id = p_service_id and s.is_active;
  if not found or not private.is_public_provider(v_svc.provider_id) then
    raise exception 'service_not_available' using errcode = 'P0002';
  end if;
  if v_svc.provider_id = v_uid then
    raise exception 'cannot_buy_your_own_service' using errcode = '42501';
  end if;
  if private.is_blocked_between(v_uid, v_svc.provider_id) then
    raise exception 'order_not_allowed' using errcode = '42501';
  end if;

  if v_req is not null and char_length(v_req) > 4000 then
    raise exception 'requirements_too_long' using errcode = '22001';
  end if;
  if v_svc.requirements_prompt is not null and v_req is null then
    raise exception 'requirements_required' using errcode = '22023';
  end if;

  -- Free any unpaid orders that have timed out, then cap how many one account
  -- can leave open.
  update public.service_orders
     set status = 'expired'
   where status = 'pending_payment'
     and payment_expires_at <= now()
     and customer_id = v_uid;
  if (select count(*) from public.service_orders o
       where o.customer_id = v_uid and o.status = 'pending_payment') >= 5 then
    raise exception 'too_many_unpaid_orders' using errcode = '54000';
  end if;

  select * into v_set from public.platform_settings;
  v_fee := (v_svc.price_minor * v_set.service_fee_bps) / 10000;

  insert into public.service_orders (
    customer_id, provider_id, service_id, title, description, deliverable_scope,
    requirements_prompt, delivery_days, price_minor, currency, platform_fee_bps,
    platform_fee_minor, provider_earnings_minor, requirements_response, payment_expires_at
  ) values (
    v_uid, v_svc.provider_id, v_svc.id, v_svc.title, v_svc.description, v_svc.deliverable_scope,
    v_svc.requirements_prompt, v_svc.delivery_days, v_svc.price_minor, v_svc.currency,
    v_set.service_fee_bps, v_fee, v_svc.price_minor - v_fee, v_req,
    now() + v_set.payment_window_minutes * interval '1 minute'
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Run on a schedule by the server.
create function public.expire_service_order_holds()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.service_orders
     set status = 'expired'
   where status = 'pending_payment'
     and payment_expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.create_service_order(uuid, text) from public, anon, authenticated;
revoke all on function public.expire_service_order_holds() from public, anon, authenticated;
grant execute on function public.create_service_order(uuid, text) to authenticated, service_role;
grant execute on function public.expire_service_order_holds() to service_role;
