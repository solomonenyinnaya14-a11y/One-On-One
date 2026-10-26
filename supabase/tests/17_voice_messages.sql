-- Voice message storage and RPC access stay private and participant-scoped.
do $$
begin
  if not exists (select 1 from storage.buckets where id='voice-messages' and public=false and file_size_limit=10485760) then
    raise exception 'voice-messages must be a private bucket capped at 10 MB';
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='voice_messages_participant_read') then
    raise exception 'voice messages need a participant-only read policy';
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='voice_messages_owner_upload') then
    raise exception 'voice messages need an owner upload policy';
  end if;
  if not has_function_privilege('authenticated','public.send_voice_message(uuid,text)','EXECUTE') then
    raise exception 'signed-in users must send voice messages through guarded RPC';
  end if;
  if has_function_privilege('anon','public.send_voice_message(uuid,text)','EXECUTE') then
    raise exception 'anonymous users must not send voice messages';
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.messages'::regclass and conname='messages_kind_valid') then
    raise exception 'message kinds constraint missing';
  end if;
end; $$;
