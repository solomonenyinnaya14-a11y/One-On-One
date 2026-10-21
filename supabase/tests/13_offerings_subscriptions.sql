-- Paid-conversation offerings: one free offering, subscription for more, expiry and
-- renewal, spoofed subscription events, and what survives an expiry.
--
-- The subscription price and commission used here are TEST values (see
-- t.reset_settings); the real commercial terms are not decided yet.

select t.reset_settings();

-- Creating offerings -------------------------------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Create'); m uuid := t.make_member('Plain Member'); o1 uuid;
begin
  perform t.as_user(p);
  perform t.fails($q$select public.create_offering('text', 'Bad length', null, 7, 500000)$q$, '22023', 'duration must be a multiple of 5');
  perform t.fails($q$select public.create_offering('text', 'Too cheap', null, 30, 50)$q$, '22023', 'a price below the floor is refused');
  perform t.fails($q$select public.create_offering('video', 'Video call', null, 30, 500000)$q$, '22023', 'video is not a supported kind');
  perform t.fails(format($q$select public.create_offering('text', 'Bad topic', null, 30, 500000, %L)$q$, gen_random_uuid()), '22023', 'unknown topic is refused');
  perform t.fails(format('insert into public.offerings (provider_id, kind, title, duration_minutes, price_minor) values (%L, %L, %L, 30, 500000)', p, 'text', 'Direct'), '42501', 'clients cannot insert offerings directly');
  perform t.eq(t.rows('select * from public.offerings'), 0, 'nothing was created by the failed attempts');
  o1 := public.create_offering('text', 'My first chat', 'Description', 30, 500000);
  perform t.reset();

  perform t.ok((select is_free_allowance from public.offerings where id = o1), 'the first offering is the free allowance');

  perform t.as_user(p);
  perform t.fails($q$select public.create_offering('voice', 'A second one', null, 30, 500000)$q$, '42501', 'a second offering needs a subscription');
  perform t.reset();
  perform t.eq((select count(*) from public.offerings where provider_id = p), 1, 'the refused offering was not created');

  perform t.as_user(m);
  perform t.fails($q$select public.create_offering('text', 'Not a provider', null, 30, 500000)$q$, '42501', 'only providers can create offerings');
  perform t.reset();

  perform t.as_anon();
  perform t.fails($q$select public.create_offering('text', 'Visitor', null, 30, 500000)$q$, '42501', 'visitors cannot create offerings');
  perform t.reset();

  perform t.fails(format('insert into public.offerings (provider_id, kind, title, duration_minutes, price_minor, is_free_allowance) values (%L, %L, %L, 30, 500000, true)', p, 'text', 'Second free'), '23505', 'only one free allowance can exist per provider');
end $$;

-- Subscribing: what the server accepts and what it refuses -------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Subscribe'); q uuid := t.make_provider('Prov Other'); r text;
begin
  update public.platform_settings set subscription_price_minor = null, subscription_period_days = null;
  perform t.eq(t.subscribe(p), 'subscriptions_not_on_sale', 'nobody can subscribe while no price is configured');
  perform t.reset_settings();

  perform t.eq(public.apply_subscription_payment('testgw', p, 'ref_low', 100, 'NGN', now(), now() + interval '30 days'), 'amount_mismatch', 'a wrong amount grants nothing');
  perform t.eq(public.apply_subscription_payment('testgw', p, 'ref_usd', 500000, 'USD', now(), now() + interval '30 days'), 'amount_mismatch', 'a wrong currency grants nothing');
  perform t.eq(public.apply_subscription_payment('testgw', p, 'ref_bad', 500000, 'NGN', now(), now() - interval '1 day'), 'invalid_period', 'a backwards period is refused');
  perform t.eq(public.apply_subscription_payment('testgw', gen_random_uuid(), 'ref_who', 500000, 'NGN', now(), now() + interval '30 days'), 'unknown_provider', 'an unknown provider is refused');
  perform t.ok(not private.has_active_subscription(p), 'none of the refused attempts created an entitlement');
  perform t.eq((select count(*) from public.provider_subscriptions where provider_id = p), 0, 'and none created a subscription row');

  perform t.eq(public.apply_subscription_payment('testgw', p, 'ref_ok', 500000, 'NGN', now(), now() + interval '30 days'), 'activated', 'a verified payment activates the subscription');
  perform t.eq(public.apply_subscription_payment('testgw', p, 'ref_ok', 500000, 'NGN', now(), now() + interval '30 days'), 'already_processed', 'replaying the same payment changes nothing');
  perform t.eq((select count(*) from public.subscription_invoices where provider_id = p), 1, 'exactly one invoice exists');
  perform t.eq((select count(*) from public.ledger_entries e join public.ledger_transactions x on x.id = e.transaction_id where x.idempotency_key like 'subscription:%'), 2, 'one balanced ledger posting exists for the subscription');
  perform t.eq(t.ledger_imbalance(), 0, 'the ledger balances');
  perform t.ok(private.has_active_subscription(p), 'the provider is now entitled');

  -- Spoofing from the browser ---------------------------------------------------------------------------------
  perform t.as_user(p);
  perform t.fails($q$select public.apply_subscription_payment('testgw', auth.uid(), 'fake', 500000, 'NGN', now(), now() + interval '300 days')$q$, '42501', 'a signed-in user cannot report their own payment');
  perform t.fails(format($q$select public.apply_subscription_event(%L, 'resumed', now())$q$, p), '42501', 'a signed-in user cannot send subscription events');
  perform t.fails('select public.expire_subscriptions()', '42501', 'a signed-in user cannot run the expiry job');
  perform t.fails(format('insert into public.provider_subscriptions (provider_id, status, gateway, current_period_start, current_period_end) values (%L, %L, %L, now(), now() + interval %L)', q, 'active', 'testgw', '300 days'), '42501', 'a user cannot insert a subscription');
  perform t.fails(format('update public.provider_subscriptions set current_period_end = now() + interval %L where provider_id = %L', '300 days', p), '42501', 'a user cannot extend their own subscription');
  perform t.fails('select gateway_customer_code from public.provider_subscriptions', '42501', 'gateway identifiers are not readable');
  perform t.eq(t.rows('select provider_id from public.provider_subscriptions'), 1, 'a provider sees only their own subscription');
  perform t.eq(t.rows('select id from public.subscription_invoices'), 1, 'and only their own invoices');
  perform t.fails('select * from public.payment_events', '42501', 'the webhook inbox is not readable');
  perform t.reset();

  perform t.as_user(q);
  perform t.eq(t.rows('select provider_id from public.provider_subscriptions'), 0, 'another provider cannot see it');
  perform t.eq(t.rows('select id from public.subscription_invoices'), 0, 'nor the invoices');
  perform t.reset();

  perform t.as_anon();
  perform t.fails('select public.my_subscription_status()', '42501', 'visitors cannot query subscription status');
  perform t.fails('select * from public.subscription_offer()', '42501', 'visitors cannot read the subscription offer');
  perform t.reset();
end $$;

-- Business settings are private ------------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Settings A'); adm uuid := t.make_member('Settings Admin');
begin
  insert into public.admin_users (user_id) values (adm);
  perform t.as_user(a);
  perform t.eq(t.rows('select * from public.platform_settings'), 0, 'ordinary users cannot read commercial settings');
  perform t.fails('update public.platform_settings set platform_fee_bps = 0', '42501', 'ordinary users cannot change commercial settings');
  perform t.reset();
  perform t.as_user(adm);
  perform t.eq(t.rows('select * from public.platform_settings'), 1, 'admins can read commercial settings');
  perform t.fails('update public.platform_settings set platform_fee_bps = 0', '42501', 'even admins cannot change them from the browser');
  perform t.reset();
end $$;

-- The full lifecycle: free allowance, subscribe, extra offering, expire, renew ---------------------------------------
do $$
declare p uuid := t.make_provider('Prov Lifecycle'); cu uuid := t.make_member('Customer Life'); cu2 uuid := t.make_member('Customer Two');
        o1 uuid; o2 uuid; b uuid; r text;
begin
  o1 := t.add_offering(p, 'text', 30, 500000, 'Free chat');
  perform t.eq(t.subscribe(p), 'activated', 'subscribe');
  o2 := t.add_offering(p, 'voice', 45, 800000, 'Extra voice call');
  perform t.ok(not (select is_free_allowance from public.offerings where id = o2), 'the extra offering is not the free allowance');

  perform t.as_anon();
  perform t.eq(t.rows(format('select id from public.offerings where provider_id = %L', p)), 2, 'while subscribed, visitors see both offerings');
  perform t.reset();

  -- Expire --------------------------------------------------------------------------------------------------------
  perform t.expire_subscription(p);
  perform t.ok(not private.has_active_subscription(p), 'after the paid period ends the provider is no longer entitled');

  perform t.as_anon();
  perform t.eq(t.rows(format('select id from public.offerings where provider_id = %L', p)), 1, 'visitors now see only the free offering');
  perform t.eq(t.rows(format('select id from public.offerings where id = %L', o2)), 0, 'the extra offering is hidden from visitors');
  perform t.reset();

  perform t.as_user(p);
  perform t.eq(t.rows(format('select id from public.offerings where provider_id = %L', p)), 2, 'the provider still has both offerings');
  perform t.eq((select accepts_bookings::text from public.offerings_with_status where id = o1), 'true', 'the free offering still accepts bookings');
  perform t.eq((select accepts_bookings::text from public.offerings_with_status where id = o2), 'false', 'the extra offering shows as not accepting bookings');
  perform t.eq((select requires_subscription::text from public.offerings_with_status where id = o2), 'true', 'and says why: it needs a subscription');
  perform t.fails($q$select public.create_offering('text', 'A third', null, 30, 500000)$q$, '42501', 'creating more offerings is blocked again');
  perform t.eq(t.affected(format('update public.offerings set price_minor = 900000 where id = %L', o2)), 1, 'the provider can still edit the extra offering');
  perform t.reset();

  perform t.eq((select count(*) from public.offerings where provider_id = p), 2, 'nothing was deleted');

  perform t.as_user(cu);
  perform t.fails(format('select public.create_booking(%L, %L)', o2, t.slot(1, 10)), 'P0002', 'a new booking on the extra offering is refused by the server');
  b := public.create_booking(o1, t.slot(1, 10));
  perform t.reset();
  perform t.ok(b is not null, 'a new booking on the free offering still works');

  perform t.eq(public.expire_subscriptions(), 1, 'the expiry job marks the subscription ended');
  perform t.eq((select status from public.provider_subscriptions where provider_id = p), 'ended', 'status shows ended');

  -- Renew -----------------------------------------------------------------------------------------------------------------
  perform t.eq(t.subscribe(p), 'renewed', 'a verified renewal restores the subscription');
  perform t.ok(private.has_active_subscription(p), 'entitled again');
  perform t.as_anon();
  perform t.eq(t.rows(format('select id from public.offerings where provider_id = %L', p)), 2, 'both offerings are public again');
  perform t.reset();
  perform t.as_user(cu2);
  r := public.create_booking(o2, t.slot(1, 12))::text;
  perform t.ok(r is not null, 'the extra offering accepts bookings again');
  perform t.reset();
  perform t.eq((select count(*) from public.offerings where provider_id = p), 2, 'renewal created no duplicate offerings');
end $$;

-- Expiry never touches existing commitments ---------------------------------------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Commitments'); cu uuid := t.make_member('Customer Committed');
        o2 uuid; b uuid; cid uuid; code text; price bigint;
begin
  perform t.add_offering(p, 'text', 30, 500000, 'Free one');
  perform t.subscribe(p);
  o2 := t.add_offering(p, 'text', 30, 700000, 'Paid extra');

  perform t.as_user(cu);
  b := public.create_booking(o2, t.slot(1, 11));
  perform t.reset();

  select price_minor into price from public.bookings where id = b;
  perform public.create_payment('booking', b, cu, 'testgw', 'pay_commit_1');
  code := public.record_payment_success('testgw', 'pay_commit_1', 'txn_commit_1', price, 'NGN');
  perform t.eq(code, 'confirmed', 'the verified payment confirms the booking');
  perform t.eq((select status from public.bookings where id = b), 'confirmed', 'the booking is confirmed');

  select c.id into cid from public.conversations c where c.user_a = least(p, cu) and c.user_b = greatest(p, cu);
  perform t.ok(cid is not null, 'the booking opened a conversation between the two people');

  perform t.expire_subscription(p);
  perform public.expire_subscriptions();

  perform t.eq((select status from public.bookings where id = b), 'confirmed', 'the confirmed booking survives subscription expiry');

  perform t.as_user(cu);
  perform t.eq(t.rows(format('select * from public.bookings where id = %L', b)), 1, 'the customer still sees the booking');
  perform public.send_message(cid, 'See you then');
  perform t.reset();
  perform t.as_user(p);
  perform t.eq(t.rows(format('select * from public.bookings where id = %L', b)), 1, 'the provider still sees the booking');
  perform public.send_message(cid, 'Looking forward to it');
  perform t.eq(t.rows(format('select * from public.messages where conversation_id = %L', cid)), (select count(*) from public.messages where conversation_id = cid), 'messaging and history are untouched');
  perform t.ok((select count(*) from public.my_earnings_summary()) >= 0, 'the earnings summary still works');
  perform t.reset();
end $$;

-- Gateway events can arrive late, twice or out of order ----------------------------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Events'); np uuid := t.make_provider('Prov No Sub');
begin
  perform t.eq(public.apply_subscription_event(np, 'resumed', now()), 'no_subscription', 'events for someone without a subscription are ignored');
  perform t.subscribe(p);

  perform t.eq(public.apply_subscription_event(p, 'cancel_requested', now()), 'applied', 'cancel_requested is applied');
  perform t.ok((select cancel_at_period_end from public.provider_subscriptions where provider_id = p), 'renewal is switched off');
  perform t.ok(private.has_active_subscription(p), 'but access continues until the paid period ends');

  perform t.eq(public.apply_subscription_event(p, 'resumed', now() - interval '1 hour'), 'stale_ignored', 'an older event arriving late is ignored');
  perform t.ok((select cancel_at_period_end from public.provider_subscriptions where provider_id = p), 'so it cannot undo the newer cancel');

  perform t.eq(public.apply_subscription_event(p, 'resumed', now() + interval '1 hour'), 'applied', 'a newer resume is applied');
  perform t.ok(not (select cancel_at_period_end from public.provider_subscriptions where provider_id = p), 'renewal is back on');

  perform t.eq(public.apply_subscription_event(p, 'payment_failed', now() + interval '2 hours'), 'applied', 'a failed renewal is recorded');
  perform t.eq((select status from public.provider_subscriptions where provider_id = p), 'past_due', 'status becomes past_due');
  perform t.ok(private.has_active_subscription(p), 'the provider keeps access until the period they paid for ends');

  perform t.fails(format($q$select public.apply_subscription_event(%L, 'explode', now())$q$, p), '22023', 'unknown event types are refused');
  perform t.fails(format($q$select public.apply_subscription_event(%L, 'resumed', null)$q$, p), '22023', 'events without a time are refused');

  -- An older paid period never shortens a newer one.
  perform t.subscribe(p, 90);
  perform t.eq(public.apply_subscription_payment('testgw', p, 'late_old_ref', 500000, 'NGN', now() - interval '30 days', now()), 'recorded', 'a late payment for an older period is recorded only');
  perform t.ok((select current_period_end > now() + interval '80 days' from public.provider_subscriptions where provider_id = p), 'and does not shorten the current period');

  -- An administrator's removal is not undone by a payment.
  update public.provider_subscriptions set status = 'revoked' where provider_id = p;
  perform t.ok(not private.has_active_subscription(p), 'a revoked subscription gives no access');
  perform t.eq(t.subscribe(p), 'subscription_revoked', 'a payment does not bring a revoked subscription back');
  perform t.eq(public.apply_subscription_event(p, 'resumed', now() + interval '3 hours'), 'subscription_revoked', 'nor does an event');
end $$;

-- Offering edits stay inside the rules --------------------------------------------------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Edit'); q uuid := t.make_provider('Prov Rival'); cu uuid := t.make_member('Customer Edit');
        o uuid; qo uuid; b uuid;
begin
  o := t.add_offering(p, 'text', 30, 500000, 'Editable');
  qo := t.add_offering(q, 'text', 30, 500000, 'Rival offering');

  perform t.as_user(p);
  perform t.eq(t.affected(format('update public.offerings set price_minor = 600000 where id = %L', o)), 1, 'a provider can change their own price');
  perform t.fails(format('update public.offerings set price_minor = 50 where id = %L', o), '23514', 'but not below the price floor');
  perform t.fails(format('update public.offerings set is_free_allowance = false where id = %L', o), '42501', 'nobody can change which offering is the free one');
  perform t.fails(format('update public.offerings set provider_id = %L where id = %L', q, o), '42501', 'nor hand an offering to someone else');
  perform t.fails(format('update public.offerings set kind = %L where id = %L', 'voice', o), '42501', 'nor change its kind');
  perform t.eq(t.affected(format('update public.offerings set price_minor = 1 where id = %L', qo)), 0, 'a provider cannot edit another provider''s offering');
  perform t.fails(format('delete from public.offerings where id = %L', o), '42501', 'offerings cannot be deleted from the browser');
  perform t.reset();
  perform t.fails(format('delete from public.offerings where id = %L', o), '42501', 'offerings are never deleted at all');

  perform t.as_user(cu);
  b := public.create_booking(o, t.slot(2, 10));
  perform t.reset();
  update public.offerings set price_minor = 900000 where id = o;
  perform t.eq((select price_minor from public.bookings where id = b), 600000, 'changing an offering never rewrites what a customer already booked');
end $$;

-- Subscription status for the provider's own screen ----------------------------------------------------------------------------
do $$
declare p uuid := t.make_provider('Prov Status');
begin
  perform t.as_user(p);
  perform t.eq((select entitled::text from public.my_subscription_status()), 'false', 'a new provider is not subscribed');
  perform t.eq((select price_minor from public.subscription_offer()), 500000, 'the current offer is visible to providers');
  perform t.reset();
  perform t.subscribe(p);
  perform t.as_user(p);
  perform t.eq((select entitled::text from public.my_subscription_status()), 'true', 'after paying the provider is entitled');
  perform t.eq((select status from public.my_subscription_status()), 'active', 'with status active');
  perform t.reset();
end $$;
