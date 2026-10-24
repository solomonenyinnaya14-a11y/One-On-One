-- TEST-ONLY helpers (schema "t"). Never applied to the real Supabase project.
--
-- Tests run as the database owner and switch into a real API role with
-- t.as_user / t.as_anon / t.as_service, exactly as Supabase does for requests.
-- t.reset() switches back. An assertion failure raises an exception, which makes
-- run.sh stop with a non-zero exit code.
--
-- Every test file is a series of DO blocks; each block is one transaction, so
-- now() is fixed inside a block. Tests that need time to pass change timestamps
-- directly as the owner.

create schema t;
grant usage on schema t to public;

create function t.ok(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'ASSERTION FAILED: %', p_msg;
  end if;
end $$;

create function t.eq(p_actual bigint, p_expected bigint, p_msg text) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'ASSERTION FAILED: % (expected %, got %)', p_msg, p_expected, p_actual;
  end if;
end $$;

create function t.eq(p_actual text, p_expected text, p_msg text) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'ASSERTION FAILED: % (expected %, got %)', p_msg, p_expected, p_actual;
  end if;
end $$;

-- Asserts that a statement is refused. Optionally also checks the SQLSTATE:
--   42501 permission denied / row-level security / forbidden
--   23514 check violation or state-machine rule   23505 unique   23503 foreign key
--   23P01 exclusion (slot taken)   22023 invalid input   54000 rate limit
--   P0002 not found
create function t.fails(p_sql text, p_state text default null, p_msg text default null) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_state is not null and sqlstate <> p_state then
      raise exception 'ASSERTION FAILED: % : expected SQLSTATE %, got % (%)',
        coalesce(p_msg, p_sql), p_state, sqlstate, sqlerrm;
    end if;
    return;
  end;
  raise exception 'ASSERTION FAILED: expected an error but the statement succeeded: %', coalesce(p_msg, p_sql);
end $$;

-- Number of rows a query returns, as the current role sees them.
create function t.rows(p_sql text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute 'select count(*) from (' || p_sql || ') q' into n;
  return n;
end $$;

-- One scalar value (as text).
create function t.val(p_sql text) returns text
language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
end $$;

-- Rows changed by an UPDATE/DELETE (0 means row-level security hid every row).
create function t.affected(p_sql text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- Impersonation -------------------------------------------------------------

create function t.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function t.as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
end $$;

create function t.as_service() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
end $$;

create function t.reset() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Fixtures (run as the database owner) ------------------------------------------

-- Known platform rules for every test file. These are TEST values only: the real
-- commission and subscription price are still undecided product settings.
create function t.reset_settings() returns void
language sql as $$
  update public.platform_settings
     set platform_fee_bps = 1000,
         service_fee_bps = 1000,
         subscription_price_minor = 500000,
         subscription_period_days = 30,
         min_booking_lead_minutes = 30,
         payment_window_minutes = 15,
         free_cancellation_hours = 24,
         earnings_hold_hours = 24,
         service_auto_release_days = 3,
         request_message_limit = 3,
         min_payout_minor = 100000;
$$;

-- A raw account (sign-up only: no username, not onboarded).
create function t.make_user(p_name text) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into auth.users (email, raw_user_meta_data)
  values (lower(replace(p_name, ' ', '.')) || '-' || substr(md5(random()::text), 1, 8) || '@example.test',
          jsonb_build_object('display_name', p_name))
  returning id into v;
  return v;
end $$;

-- An onboarded member who shows up in discovery.
create function t.make_member(p_name text) returns uuid
language plpgsql as $$
declare v uuid := t.make_user(p_name);
begin
  update public.profiles
     set username = 'u' || substr(md5(random()::text), 1, 12),
         onboarding_completed_at = now()
   where id = v;
  return v;
end $$;

-- An approved provider, open 09:00-17:00 every day in Africa/Lagos time.
create function t.make_provider(p_name text) returns uuid
language plpgsql as $$
declare v uuid := t.make_member(p_name);
begin
  insert into public.provider_profiles (user_id, headline, about, status)
  values (v, 'Headline for ' || p_name, 'About ' || p_name, 'approved');
  insert into public.availability_rules (provider_id, weekday, start_time, end_time)
  select v, d, time '09:00', time '17:00' from generate_series(0, 6) d;
  return v;
end $$;

-- A moment in Africa/Lagos time: p_days from today at hh:mm.
create function t.slot(p_days integer, p_hour integer, p_minute integer default 0) returns timestamptz
language sql stable as $$
  select (date_trunc('day', now() at time zone 'Africa/Lagos')
          + make_interval(days => p_days, hours => p_hour, mins => p_minute))
         at time zone 'Africa/Lagos';
$$;

-- Gives a provider an active subscription through the real server function.
create function t.subscribe(p_provider uuid, p_days integer default 30, p_ref text default null) returns text
language plpgsql as $$
begin
  return public.apply_subscription_payment(
    'testgw', p_provider, coalesce(p_ref, 'sub_' || md5(random()::text)),
    500000, 'NGN', now(), now() + make_interval(days => p_days));
end $$;

-- Pretends time has passed for a subscription (owner-only shortcut for tests).
create function t.expire_subscription(p_provider uuid) returns void
language sql as $$
  update public.provider_subscriptions
     set current_period_start = now() - interval '60 days',
         current_period_end = now() - interval '1 day'
   where provider_id = p_provider;
$$;

-- Creates an offering exactly as the provider would, through create_offering().
create function t.add_offering(p_provider uuid, p_kind text default 'text', p_minutes integer default 30,
                               p_price bigint default 500000, p_title text default null) returns uuid
language plpgsql as $$
declare v uuid;
begin
  perform t.as_user(p_provider);
  v := public.create_offering(p_kind, coalesce(p_title, 'A ' || p_minutes || ' minute ' || p_kind || ' chat'),
                              null, p_minutes, p_price);
  perform t.reset();
  return v;
end $$;

-- Debits minus credits across the whole ledger (must always be 0).
create function t.ledger_imbalance() returns bigint
language sql as $$
  select coalesce(sum(case direction when 'debit' then amount_minor else -amount_minor end), 0)::bigint
    from public.ledger_entries;
$$;
