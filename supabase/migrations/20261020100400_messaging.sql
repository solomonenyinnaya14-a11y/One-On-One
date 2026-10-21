-- One On One migration 05: free one-to-one messaging.
--
-- Free messaging is a core feature and is completely independent of bookings:
--   * A conversation is one row per pair of people, enforced by the database
--     (user_a < user_b with a unique pair), so tapping "Message" repeatedly can
--     never create a duplicate.
--   * Messages are written ONLY through send_message(), which enforces blocking,
--     account status, message-request limits and rate limits on the server.
--   * Only the two participants can read a conversation. There is deliberately no
--     admin read policy; moderators can read a conversation only through an
--     audited function tied to an open report (migration 10).
--   * Booking and service-order "cards" are messages that POINT to the real
--     record (booking_id / service_order_id). They carry no booking data of their
--     own, so they can never disagree with the booking.
--
-- Message-request policy (MVP):
--   * A stranger's first conversation starts as a REQUEST. They may send up to
--     platform_settings.request_message_limit messages (default 3) before the
--     recipient responds.
--   * The recipient can accept (conversation becomes active), decline (the sender
--     cannot send more and cannot start another request), or simply reply, which
--     counts as accepting.
--   * People can switch off free chats entirely (profiles.accepts_free_chats).
--     Paid bookings always open an active conversation for the two parties.

set search_path = public, extensions;

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  -- user_a < user_b always, so each pair has exactly one possible row.
  user_a uuid not null references public.profiles (id) on delete restrict,
  user_b uuid not null references public.profiles (id) on delete restrict,
  initiator_id uuid not null references public.profiles (id) on delete restrict,
  status text not null default 'request',
  accepted_at timestamptz,
  last_message_at timestamptz,
  last_message_preview text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_ordered check (user_a < user_b),
  constraint conversations_pair_key unique (user_a, user_b),
  constraint conversations_initiator_member check (initiator_id in (user_a, user_b)),
  constraint conversations_status_valid check (status in ('request', 'active', 'declined')),
  constraint conversations_preview_length check (last_message_preview is null or char_length(last_message_preview) <= 140)
);

-- Inbox queries: "my conversations, most recent first".
create index conversations_user_a_idx on public.conversations (user_a, last_message_at desc nulls last);
create index conversations_user_b_idx on public.conversations (user_b, last_message_at desc nulls last);
create index conversations_initiator_idx on public.conversations (initiator_id, created_at desc);

create trigger conversations_set_updated_at
  before update on public.conversations
  for each row execute function private.set_updated_at();

create trigger conversations_forbid_delete
  before delete on public.conversations
  for each row execute function private.forbid_delete();

-- Identity of a conversation never changes.
create function private.guard_conversation_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.user_a, new.user_b, new.initiator_id, new.created_at)
     is distinct from (old.user_a, old.user_b, old.initiator_id, old.created_at) then
    raise exception 'conversation_identity_is_immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger conversations_guard_update
  before update on public.conversations
  for each row execute function private.guard_conversation_update();

create function private.is_conversation_participant(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = p_conversation
      and (select auth.uid()) in (c.user_a, c.user_b)
  );
$$;

-- True when the signed-in user and p_other share a conversation. Lets people see
-- the basic profile of someone they are talking to, even if that person later
-- hides from discovery.
create function private.shares_conversation_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversations c
    where c.user_a = least((select auth.uid()), p_other)
      and c.user_b = greatest((select auth.uid()), p_other)
      and (select auth.uid()) <> p_other
  );
$$;

create policy profiles_select_conversation_peer on public.profiles
  for select to authenticated
  using (private.shares_conversation_with(id));

alter table public.conversations enable row level security;
revoke all on public.conversations from anon, authenticated;
grant select on public.conversations to authenticated;

create policy conversations_select_participant on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

-- Read pointers (unread indicators) ----------------------------------------------

create table public.conversation_reads (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

alter table public.conversation_reads enable row level security;
revoke all on public.conversation_reads from anon, authenticated;
grant select on public.conversation_reads to authenticated;

create policy conversation_reads_select_own on public.conversation_reads
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Messages ---------------------------------------------------------------------

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete restrict,
  -- Null for cards and system messages, which are written by the server only.
  sender_id uuid references public.profiles (id) on delete restrict,
  kind text not null default 'user',
  body text,
  -- Cards point at the real record. Foreign keys are added in migrations 06/07.
  booking_id uuid,
  service_order_id uuid,
  created_at timestamptz not null default now(),
  constraint messages_kind_valid check (kind in ('user', 'booking_card', 'service_card', 'system')),
  constraint messages_shape_valid check (
    (kind = 'user' and sender_id is not null and booking_id is null and service_order_id is null
       and body is not null and char_length(btrim(body)) between 1 and 4000)
    or (kind = 'booking_card' and sender_id is null and booking_id is not null
       and service_order_id is null and body is null)
    or (kind = 'service_card' and sender_id is null and service_order_id is not null
       and booking_id is null and body is null)
    or (kind = 'system' and sender_id is null and booking_id is null and service_order_id is null
       and body is not null and char_length(body) <= 500)
  )
);

create index messages_conversation_idx on public.messages (conversation_id, created_at, id);
create index messages_sender_recent_idx on public.messages (sender_id, created_at desc)
  where sender_id is not null;

create trigger messages_append_only
  before update or delete on public.messages
  for each row execute function private.forbid_change();
create trigger messages_no_truncate
  before truncate on public.messages
  for each statement execute function private.forbid_truncate();

-- Keeps the inbox row (preview and ordering) in step with the newest message.
create function private.touch_conversation_on_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations c
     set last_message_at = new.created_at,
         last_message_preview = case new.kind
           when 'user' then left(regexp_replace(btrim(new.body), '\s+', ' ', 'g'), 140)
           when 'booking_card' then 'Booking update'
           when 'service_card' then 'Service order update'
           else left(new.body, 140)
         end
   where c.id = new.conversation_id;
  return null;
end;
$$;

create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function private.touch_conversation_on_message();

alter table public.messages enable row level security;
revoke all on public.messages from anon, authenticated;
-- Read only. Nobody inserts, edits or deletes messages directly.
grant select on public.messages to authenticated;

create policy messages_select_participant on public.messages
  for select to authenticated
  using (private.is_conversation_participant(conversation_id));

-- Live updates: Supabase Realtime evaluates the select policies above for every
-- subscriber, so people only receive rows from their own conversations.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages;
    alter publication supabase_realtime add table public.conversations;
  end if;
end
$$;

-- Starting and replying ------------------------------------------------------------

-- Gets the conversation between two people, creating an ACTIVE one if none
-- exists. Used by paid bookings and service orders, where the customer has paid
-- a provider who publicly offered that product. Never exposed to clients.
create function private.ensure_active_conversation(p_a uuid, p_b uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lo uuid := least(p_a, p_b);
  v_hi uuid := greatest(p_a, p_b);
  v_id uuid;
begin
  insert into public.conversations (user_a, user_b, initiator_id, status, accepted_at)
  values (v_lo, v_hi, p_a, 'active', now())
  on conflict (user_a, user_b) do nothing
  returning id into v_id;

  if v_id is null then
    update public.conversations
       set status = 'active', accepted_at = coalesce(accepted_at, now())
     where user_a = v_lo and user_b = v_hi
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

-- Returns the existing conversation with p_other, or opens a new message request.
-- Calling it twice returns the same conversation: this is what the profile's
-- "Message" button uses.
create function public.start_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_lo uuid;
  v_hi uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_other is null or p_other = v_uid then
    raise exception 'invalid_recipient' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other and p.status = 'active') then
    raise exception 'recipient_unavailable' using errcode = 'P0002';
  end if;
  if private.is_blocked_between(v_uid, p_other) then
    raise exception 'conversation_not_allowed' using errcode = '42501';
  end if;

  v_lo := least(v_uid, p_other);
  v_hi := greatest(v_uid, p_other);

  select c.id into v_id from public.conversations c where c.user_a = v_lo and c.user_b = v_hi;
  if found then
    return v_id;
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_other and p.accepts_free_chats) then
    raise exception 'not_accepting_free_chats' using errcode = '42501';
  end if;

  -- Spam control: a limited number of NEW conversations per person per day.
  if (select count(*) from public.conversations c
       where c.initiator_id = v_uid and c.created_at > now() - interval '24 hours') >= 20 then
    raise exception 'rate_limited' using errcode = '54000';
  end if;

  insert into public.conversations (user_a, user_b, initiator_id, status)
  values (v_lo, v_hi, v_uid, 'request')
  on conflict (user_a, user_b) do nothing
  returning id into v_id;

  if v_id is null then
    -- Lost a race with the other person starting the same conversation.
    select c.id into v_id from public.conversations c where c.user_a = v_lo and c.user_b = v_hi;
  end if;
  return v_id;
end;
$$;

-- The only way to send a message.
create function public.send_message(p_conversation uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_c public.conversations%rowtype;
  v_body text := btrim(coalesce(p_body, ''));
  v_other uuid;
  v_limit integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_body) not between 1 and 4000 then
    raise exception 'invalid_message' using errcode = '22023';
  end if;

  -- Lock the conversation so that the request limit cannot be beaten by
  -- sending several messages at the same moment.
  select * into v_c from public.conversations c where c.id = p_conversation for update;
  if not found or v_uid not in (v_c.user_a, v_c.user_b) then
    raise exception 'conversation_not_found' using errcode = 'P0002';
  end if;
  v_other := case when v_uid = v_c.user_a then v_c.user_b else v_c.user_a end;

  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_other and p.status = 'active') then
    raise exception 'recipient_unavailable' using errcode = '42501';
  end if;
  if private.is_blocked_between(v_uid, v_other) then
    raise exception 'conversation_not_allowed' using errcode = '42501';
  end if;

  if v_c.status = 'declined' then
    raise exception 'conversation_declined' using errcode = '42501';
  end if;

  if (select count(*) from public.messages m
       where m.sender_id = v_uid and m.created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited' using errcode = '54000';
  end if;

  if v_c.status = 'request' then
    if v_uid = v_c.initiator_id then
      select s.request_message_limit into v_limit from public.platform_settings s;
      if (select count(*) from public.messages m
           where m.conversation_id = v_c.id and m.sender_id = v_uid) >= v_limit then
        raise exception 'request_limit_reached' using errcode = '54000';
      end if;
    else
      -- The recipient replying is accepting the request.
      update public.conversations
         set status = 'active', accepted_at = now()
       where id = v_c.id;
    end if;
  end if;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (v_c.id, v_uid, 'user', v_body)
  returning id into v_id;

  -- Sending a message means you have read everything up to now.
  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (v_c.id, v_uid, now())
  on conflict (conversation_id, user_id) do update set last_read_at = excluded.last_read_at;

  return v_id;
end;
$$;

-- Recipient's answer to a message request.
create function public.respond_to_message_request(p_conversation uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_c public.conversations%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_c from public.conversations c where c.id = p_conversation for update;
  if not found or v_uid not in (v_c.user_a, v_c.user_b) then
    raise exception 'conversation_not_found' using errcode = 'P0002';
  end if;
  if v_uid = v_c.initiator_id then
    raise exception 'only_the_recipient_can_respond' using errcode = '42501';
  end if;
  if private.is_blocked_between(v_c.user_a, v_c.user_b) then
    raise exception 'conversation_not_allowed' using errcode = '42501';
  end if;

  if p_accept then
    update public.conversations
       set status = 'active', accepted_at = coalesce(accepted_at, now())
     where id = v_c.id;
    return 'active';
  end if;

  if v_c.status <> 'request' then
    raise exception 'request_already_answered' using errcode = '23514';
  end if;
  update public.conversations set status = 'declined' where id = v_c.id;
  return 'declined';
end;
$$;

create function public.mark_conversation_read(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not private.is_conversation_participant(p_conversation) then
    raise exception 'conversation_not_found' using errcode = 'P0002';
  end if;

  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conversation, v_uid, now())
  on conflict (conversation_id, user_id) do update set last_read_at = excluded.last_read_at;
end;
$$;

-- The Messages tab: my conversations, newest activity first, with unread counts.
-- Runs with the caller's permissions, so it can only ever return their own rows.
create function public.my_inbox(p_limit integer default 30, p_offset integer default 0)
returns table (
  conversation_id uuid,
  status text,
  i_started boolean,
  other_user_id uuid,
  other_username text,
  other_display_name text,
  other_avatar_path text,
  last_message_at timestamptz,
  last_message_preview text,
  unread_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id,
         c.status,
         c.initiator_id = (select auth.uid()),
         o.id,
         o.username,
         o.display_name,
         o.avatar_path,
         c.last_message_at,
         c.last_message_preview,
         (select count(*)
            from public.messages m
           where m.conversation_id = c.id
             and m.sender_id is distinct from (select auth.uid())
             and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz))
    from public.conversations c
    join public.profiles o
      on o.id = case when c.user_a = (select auth.uid()) then c.user_b else c.user_a end
    left join public.conversation_reads r
      on r.conversation_id = c.id and r.user_id = (select auth.uid())
   where (select auth.uid()) in (c.user_a, c.user_b)
     and c.last_message_at is not null
   order by c.last_message_at desc, c.id
   limit least(greatest(coalesce(p_limit, 30), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- Number shown on the Messages tab badge.
create function public.my_unread_count()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)
    from public.conversations c
    join public.messages m on m.conversation_id = c.id
    left join public.conversation_reads r
      on r.conversation_id = c.id and r.user_id = (select auth.uid())
   where (select auth.uid()) in (c.user_a, c.user_b)
     and c.status <> 'declined'
     and m.sender_id is distinct from (select auth.uid())
     and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz);
$$;

revoke all on function public.start_conversation(uuid) from public, anon, authenticated;
revoke all on function public.send_message(uuid, text) from public, anon, authenticated;
revoke all on function public.respond_to_message_request(uuid, boolean) from public, anon, authenticated;
revoke all on function public.mark_conversation_read(uuid) from public, anon, authenticated;
revoke all on function public.my_inbox(integer, integer) from public, anon, authenticated;
revoke all on function public.my_unread_count() from public, anon, authenticated;

grant execute on function public.start_conversation(uuid) to authenticated, service_role;
grant execute on function public.send_message(uuid, text) to authenticated, service_role;
grant execute on function public.respond_to_message_request(uuid, boolean) to authenticated, service_role;
grant execute on function public.mark_conversation_read(uuid) to authenticated, service_role;
grant execute on function public.my_inbox(integer, integer) to authenticated, service_role;
grant execute on function public.my_unread_count() to authenticated, service_role;
