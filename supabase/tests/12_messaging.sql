-- Free messaging: one conversation per pair, message requests, blocking, privacy,
-- unread counts, inbox ordering, rate limits.

-- One conversation per pair ------------------------------------------------------
do $$
declare a uuid := t.make_member('Ann'); b uuid := t.make_member('Ben');
        c1 uuid; c2 uuid; c3 uuid; lo uuid := least(a, b); hi uuid := greatest(a, b);
begin
  perform t.as_user(a);
  c1 := public.start_conversation(b);
  c2 := public.start_conversation(b);
  perform t.eq(c1::text, c2::text, 'tapping Message twice returns the same conversation');
  perform t.reset();

  perform t.as_user(b);
  c3 := public.start_conversation(a);
  perform t.eq(c3::text, c1::text, 'the other person starting a chat reuses the same conversation');
  perform t.reset();

  perform t.eq((select count(*) from public.conversations where user_a = lo and user_b = hi), 1, 'exactly one row exists for the pair');

  perform t.fails(format('insert into public.conversations (user_a, user_b, initiator_id) values (%L, %L, %L)', lo, hi, a), '23505', 'the database refuses a duplicate pair');
  perform t.fails(format('insert into public.conversations (user_a, user_b, initiator_id) values (%L, %L, %L)', hi, lo, a), '23514', 'the database refuses the pair in reverse order');

  perform t.as_user(a);
  perform t.fails(format('select public.start_conversation(%L)', a), '22023', 'you cannot start a chat with yourself');
  perform t.fails(format('insert into public.conversations (user_a, user_b, initiator_id) values (%L, %L, %L)', lo, hi, a), '42501', 'clients cannot create conversations directly');
  perform t.reset();

  perform t.as_anon();
  perform t.fails(format('select public.start_conversation(%L)', b), '42501', 'visitors cannot start conversations');
  perform t.reset();
end $$;

-- People can switch off free chats ----------------------------------------------------
do $$
declare a uuid := t.make_member('Open A'); b uuid := t.make_member('Closed B'); c uuid := t.make_member('Closed C');
        existing uuid;
begin
  perform t.as_user(a);
  existing := public.start_conversation(b);
  perform t.reset();

  update public.profiles set accepts_free_chats = false where id in (b, c);

  perform t.as_user(a);
  perform t.fails(format('select public.start_conversation(%L)', c), '42501', 'a new chat with someone who turned chats off is refused');
  perform t.eq(public.start_conversation(b)::text, existing::text, 'an existing conversation is still reachable');
  perform t.reset();
end $$;

-- Message requests and the request limit ---------------------------------------------------
do $$
declare a uuid := t.make_member('Stranger A'); b uuid := t.make_member('Recipient B'); cid uuid;
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  perform public.send_message(cid, 'Hello 1');
  perform public.send_message(cid, 'Hello 2');
  perform public.send_message(cid, 'Hello 3');
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'Hello 4'), '54000', 'a stranger is stopped after the request limit');
  perform t.reset();

  perform t.eq((select status from public.conversations where id = cid), 'request', 'the conversation is still a request');

  perform t.as_user(b);
  perform t.eq(t.rows('select * from public.messages'), 3, 'the recipient can read the request');
  perform public.send_message(cid, 'Hi A, glad you wrote');
  perform t.reset();
  perform t.eq((select status from public.conversations where id = cid), 'active', 'replying accepts the request');

  perform t.as_user(a);
  perform public.send_message(cid, 'Hello 4, now allowed');
  perform t.eq(t.rows('select * from public.messages'), 5, 'the sender now sees the whole history');
  perform t.reset();
end $$;

-- Declining a request ----------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Asker'); b uuid := t.make_member('Decliner'); cid uuid;
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  perform public.send_message(cid, 'Can we talk?');
  perform t.fails(format('select public.respond_to_message_request(%L, true)', cid), '42501', 'the sender cannot accept their own request');
  perform t.reset();

  perform t.as_user(b);
  perform t.eq(public.respond_to_message_request(cid, false), 'declined', 'the recipient can decline');
  perform t.reset();

  perform t.as_user(a);
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'Please?'), '42501', 'a declined sender cannot send more');
  perform t.eq(public.start_conversation(b)::text, cid::text, 'asking again returns the same conversation, not a new one');
  perform t.reset();
  perform t.eq((select count(*) from public.conversations where initiator_id = a), 1, 'declining does not allow a fresh request');

  perform t.as_user(b);
  perform t.eq(public.respond_to_message_request(cid, true), 'active', 'the recipient can change their mind');
  perform t.reset();
  perform t.as_user(a);
  perform public.send_message(cid, 'Thanks for reconsidering');
  perform t.reset();
end $$;

-- Blocking is enforced by the server ---------------------------------------------------------------
do $$
declare a uuid := t.make_member('Chatter A'); b uuid := t.make_member('Chatter B'); cid uuid;
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  perform public.send_message(cid, 'Before the block');
  perform t.reset();
  perform t.as_user(b);
  perform public.send_message(cid, 'Reply before the block');
  insert into public.blocks (blocker_id, blocked_id) values (b, a);
  perform t.reset();

  perform t.as_user(a);
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'After the block'), '42501', 'the blocked person cannot send');
  perform t.fails(format('select public.start_conversation(%L)', b), '42501', 'the blocked person cannot reopen the chat');
  perform t.reset();

  perform t.as_user(b);
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'I blocked you'), '42501', 'the blocker cannot send either');
  perform t.eq(t.affected(format('delete from public.blocks where blocked_id = %L', a)), 1, 'the blocker can unblock');
  perform public.send_message(cid, 'Unblocked, hello again');
  perform t.reset();
end $$;

-- Privacy: only the two participants can read or touch a conversation ---------------------------------
do $$
declare a uuid := t.make_member('Private A'); b uuid := t.make_member('Private B'); c uuid := t.make_member('Snoop C');
        cid uuid; mid uuid;
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  mid := public.send_message(cid, 'This is private');
  perform t.reset();

  perform t.as_user(c);
  perform t.eq(t.rows('select * from public.conversations'), 0, 'a third person sees no conversations');
  perform t.eq(t.rows('select * from public.messages'), 0, 'a third person sees no messages');
  perform t.eq(t.rows(format('select * from public.messages where id = %L', mid)), 0, 'guessing a message id reveals nothing');
  perform t.eq(t.rows('select * from public.my_inbox()'), 0, 'a third person''s inbox is empty');
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'butting in'), 'P0002', 'a third person cannot send into it');
  perform t.fails(format('select public.mark_conversation_read(%L)', cid), 'P0002', 'a third person cannot mark it read');
  perform t.fails(format('select public.respond_to_message_request(%L, true)', cid), 'P0002', 'a third person cannot answer the request');
  perform t.reset();

  perform t.as_anon();
  perform t.fails('select * from public.messages', '42501', 'visitors cannot read messages');
  perform t.fails('select * from public.conversations', '42501', 'visitors cannot read conversations');
  perform t.reset();

  perform t.as_user(a);
  perform t.fails(format('insert into public.messages (conversation_id, sender_id, kind, body) values (%L, %L, %L, %L)', cid, a, 'user', 'direct insert'), '42501', 'clients cannot insert messages directly');
  perform t.fails(format('update public.messages set body = %L where id = %L', 'edited', mid), '42501', 'clients cannot edit messages');
  perform t.fails(format('delete from public.messages where id = %L', mid), '42501', 'clients cannot delete messages');
  perform t.fails(format('update public.conversations set status = %L where id = %L', 'active', cid), '42501', 'clients cannot change conversation status directly');
  perform t.reset();

  perform t.fails(format('update public.messages set body = %L where id = %L', 'edited', mid), '42501', 'even the owner cannot rewrite history');
  perform t.fails(format('delete from public.messages where id = %L', mid), '42501', 'even the owner cannot delete history');
  perform t.fails(format('update public.conversations set user_b = %L where id = %L', c, cid), '42501', 'a conversation''s participants never change');
  perform t.fails(format('delete from public.conversations where id = %L', cid), '42501', 'conversations are never deleted');

  perform t.ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'messages'), 'new messages are published to Realtime (filtered by the read policy)');
end $$;

-- Cards cannot be forged ------------------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Card A'); b uuid := t.make_member('Card B'); cid uuid;
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  perform t.reset();
  perform t.fails(format('insert into public.messages (conversation_id, sender_id, kind, body, booking_id) values (%L, %L, %L, %L, %L)', cid, a, 'user', 'x', gen_random_uuid()), '23514', 'a user message cannot carry a booking pointer');
  perform t.fails(format('insert into public.messages (conversation_id, kind, booking_id) values (%L, %L, %L)', cid, 'booking_card', gen_random_uuid()), '23503', 'a booking card must point at a real booking');
end $$;

-- Inbox: peers appear even when hidden, ordering, previews, unread counts -----------------------------------------
do $$
declare v uuid := t.make_member('Viewer V'); x uuid := t.make_member('Xavier'); y uuid := t.make_member('Yetunde');
        z uuid := t.make_member('Zainab'); w uuid := t.make_member('Quiet W'); h uuid := t.make_member('Hidden H');
        cx uuid; cy uuid; cz uuid; cw uuid; ch uuid; long_text text := repeat('word ', 80);
begin
  update public.profiles set is_discoverable = false where id = h;

  perform t.as_user(v);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', h)), 0, 'a hidden person is not visible before any contact');
  perform t.reset();

  perform t.as_user(h);
  ch := public.start_conversation(v);
  perform public.send_message(ch, 'Hi from a hidden profile');
  perform t.reset();

  perform t.as_user(v);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', h)), 1, 'the person who messaged you is visible to you');
  perform t.eq(t.rows(format('select * from public.my_inbox() where other_user_id = %L', h)), 1, 'their request shows up in your inbox');
  perform t.reset();

  perform t.as_user(x); cx := public.start_conversation(v); perform public.send_message(cx, 'From X'); perform t.reset();
  perform t.as_user(y); cy := public.start_conversation(v); perform public.send_message(cy, '   Spaced    out
   preview   '); perform t.reset();
  perform t.as_user(z); cz := public.start_conversation(v); perform public.send_message(cz, long_text); perform t.reset();
  perform t.as_user(v); cw := public.start_conversation(w); perform t.reset();

  -- Spread the activity out in time (the owner may change inbox ordering data).
  update public.conversations set last_message_at = now() - interval '3 minutes' where id = cx;
  update public.conversations set last_message_at = now() - interval '2 minutes' where id = cy;
  update public.conversations set last_message_at = now() - interval '1 minute' where id = cz;
  update public.conversations set last_message_at = now() - interval '10 minutes' where id = ch;

  perform t.as_user(v);
  perform t.eq((select other_user_id::text from public.my_inbox() limit 1), z::text, 'the most recently active conversation comes first');
  perform t.eq((select string_agg(other_user_id::text, ',' order by ordinality) from (select other_user_id, row_number() over () as ordinality from public.my_inbox()) q),
               z::text || ',' || y::text || ',' || x::text || ',' || h::text, 'the inbox is ordered by latest activity');
  perform t.eq(t.rows(format('select * from public.my_inbox() where other_user_id = %L', w)), 0, 'a conversation with no messages is not listed');
  perform t.eq((select last_message_preview from public.my_inbox() where other_user_id = y), 'Spaced out preview', 'previews collapse whitespace');
  perform t.eq((select char_length(last_message_preview) from public.my_inbox() where other_user_id = z)::bigint, 140, 'previews are cut to 140 characters');
  perform t.eq((select unread_count from public.my_inbox() where other_user_id = x), 1, 'a new message is unread');
  perform t.eq(public.my_unread_count(), 4, 'the Messages badge counts every unread message');

  perform public.mark_conversation_read(cx);
  perform t.eq((select unread_count from public.my_inbox() where other_user_id = x), 0, 'reading a conversation clears its unread count');
  perform t.eq(public.my_unread_count(), 3, 'and lowers the badge');
  perform t.reset();

  perform t.as_user(x);
  perform t.eq((select unread_count from public.my_inbox() where other_user_id = v), 0, 'your own messages are never unread for you');
  perform t.reset();

  -- A new message moves its conversation to the top.
  update public.conversations set last_message_at = now() - interval '5 minutes';
  perform t.as_user(x);
  perform public.send_message(cx, 'Following up');
  perform t.reset();
  perform t.as_user(v);
  perform t.eq((select other_user_id::text from public.my_inbox() limit 1), x::text, 'a new message moves its conversation to the top');
  perform t.eq((select last_message_preview from public.my_inbox() where other_user_id = x), 'Following up', 'and updates the preview');
  perform t.reset();
end $$;

-- Rate limits and account status -----------------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Fast A'); b uuid := t.make_member('Fast B'); cid uuid; n integer;
        s uuid := t.make_member('Suspended S'); others uuid[] := '{}';
begin
  perform t.as_user(a);
  cid := public.start_conversation(b);
  perform t.reset();
  update public.conversations set status = 'active', accepted_at = now() where id = cid;

  perform t.as_user(a);
  for n in 1..30 loop
    perform public.send_message(cid, 'message ' || n);
  end loop;
  perform t.fails(format('select public.send_message(%L, %L)', cid, 'message 31'), '54000', 'more than 30 messages a minute is refused');
  perform t.reset();

  -- At most 20 new conversations per person per day.
  for n in 1..21 loop
    others := others || t.make_member('Target ' || n);
  end loop;
  perform t.as_user(a);
  for n in 1..19 loop
    perform public.start_conversation(others[n]);
  end loop;
  perform t.fails(format('select public.start_conversation(%L)', others[21]), '54000', 'the 21st new conversation in a day is refused');
  perform t.reset();

  -- Suspended accounts cannot message, and cannot be messaged.
  update public.profiles set status = 'suspended' where id = s;
  perform t.as_user(s);
  perform t.fails(format('select public.start_conversation(%L)', a), '42501', 'a suspended account cannot start chats');
  perform t.reset();
  perform t.as_user(a);
  perform t.fails(format('select public.start_conversation(%L)', s), 'P0002', 'a suspended account cannot be messaged');
  perform t.reset();
end $$;
