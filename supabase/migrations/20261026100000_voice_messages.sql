-- Private voice notes for the messaging-first MVP.
-- Audio is stored in a private bucket; only conversation participants may read it.
alter table public.messages drop constraint if exists messages_kind_valid;
alter table public.messages drop constraint if exists messages_shape_valid;

alter table public.messages
  add constraint messages_kind_valid
  check (kind in ('user', 'voice', 'booking_card', 'service_card', 'system'));

alter table public.messages
  add constraint messages_shape_valid check (
    (kind = 'user' and sender_id is not null and booking_id is null and service_order_id is null
      and body is not null and char_length(btrim(body)) between 1 and 4000)
    or (kind = 'voice' and sender_id is not null and booking_id is null and service_order_id is null
      and body is not null and char_length(body) between 1 and 500)
    or (kind = 'booking_card' and sender_id is null and booking_id is not null
      and service_order_id is null and body is null)
    or (kind = 'service_card' and sender_id is null and service_order_id is not null
      and booking_id is null and body is null)
    or (kind = 'system' and sender_id is null and booking_id is null and service_order_id is null
      and body is not null and char_length(body) <= 500)
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice-messages', 'voice-messages', false, 10485760,
        array['audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg'])
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg'];

drop policy if exists voice_messages_participant_read on storage.objects;
create policy voice_messages_participant_read on storage.objects
for select to authenticated
using (
  bucket_id = 'voice-messages'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and exists (
    select 1 from public.conversations c
    where c.id = ((storage.foldername(name))[1])::uuid
      and (select auth.uid()) in (c.user_a, c.user_b)
  )
);

drop policy if exists voice_messages_owner_upload on storage.objects;
create policy voice_messages_owner_upload on storage.objects
for insert to authenticated
with check (
  bucket_id = 'voice-messages'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.conversations c
    where c.id = ((storage.foldername(name))[1])::uuid
      and (select auth.uid()) in (c.user_a, c.user_b)
  )
);

create or replace function public.send_voice_message(p_conversation uuid, p_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_c public.conversations%rowtype;
  v_other uuid;
  v_limit integer;
  v_id uuid;
  v_object storage.objects%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_path is null
     or p_path !~ ('^' || p_conversation::text || '/' || v_uid::text || '/[0-9a-f-]{36}\.(webm|ogg|mp4|mp3)$') then
    raise exception 'invalid_voice_path' using errcode = '22023';
  end if;

  select * into v_c from public.conversations c where c.id = p_conversation for update;
  if not found or v_uid not in (v_c.user_a, v_c.user_b) then
    raise exception 'conversation_not_found' using errcode = 'P0002';
  end if;
  v_other := case when v_uid = v_c.user_a then v_c.user_b else v_c.user_a end;

  if not exists (select 1 from public.profiles p where p.id = v_uid and p.status = 'active')
     or not exists (select 1 from public.profiles p where p.id = v_other and p.status = 'active') then
    raise exception 'account_not_active' using errcode = '42501';
  end if;
  if private.is_blocked_between(v_uid, v_other) then
    raise exception 'conversation_not_allowed' using errcode = '42501';
  end if;
  if v_c.status = 'declined' then
    raise exception 'conversation_declined' using errcode = '42501';
  end if;

  select * into v_object from storage.objects o
    where o.bucket_id = 'voice-messages' and o.name = p_path;
  if not found or v_object.owner_id is distinct from v_uid::text
     or v_object.metadata->>'size' is null
     or (v_object.metadata->>'size')::bigint > 10485760
     or coalesce(v_object.metadata->>'mimetype', '') not in ('audio/webm','audio/ogg','audio/mp4','audio/mpeg') then
    raise exception 'voice_file_unavailable' using errcode = '42501';
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
      update public.conversations set status = 'active', accepted_at = now() where id = v_c.id;
    end if;
  end if;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (v_c.id, v_uid, 'voice', p_path)
  returning id into v_id;

  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (v_c.id, v_uid, now())
  on conflict (conversation_id, user_id) do update set last_read_at = excluded.last_read_at;
  return v_id;
end;
$$;

revoke all on function public.send_voice_message(uuid, text) from public, anon, authenticated;
grant execute on function public.send_voice_message(uuid, text) to authenticated;

