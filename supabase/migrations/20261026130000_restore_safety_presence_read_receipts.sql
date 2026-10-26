-- Restore presence and peer-read RPCs used by the Settings and chat UI.
-- The original safety migration was not applied to the connected One On One project.
create or replace function public.heartbeat_presence()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_seen timestamptz := now();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  update public.profiles
     set last_seen_at = case when show_online_status then v_seen else null end
   where id = v_uid and status = 'active';
  return v_seen;
end;
$$;
revoke all on function public.heartbeat_presence() from public, anon, authenticated;
grant execute on function public.heartbeat_presence() to authenticated, service_role;

create or replace function public.conversation_peer_read_at(p_conversation uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_peer uuid;
  v_read timestamptz;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select case when c.user_a = v_uid then c.user_b else c.user_a end
    into v_peer
    from public.conversations c
   where c.id = p_conversation and v_uid in (c.user_a, c.user_b);
  if v_peer is null then raise exception 'conversation_not_allowed' using errcode = '42501'; end if;
  select r.last_read_at into v_read
    from public.conversation_reads r
   where r.conversation_id = p_conversation and r.user_id = v_peer;
  return v_read;
end;
$$;
revoke all on function public.conversation_peer_read_at(uuid) from public, anon, authenticated;
grant execute on function public.conversation_peer_read_at(uuid) to authenticated, service_role;
