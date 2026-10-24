do $$
begin
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='last_seen_at') then raise exception 'profiles.last_seen_at missing'; end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='show_online_status') then raise exception 'profiles.show_online_status missing'; end if;
 if not (select relrowsecurity from pg_class where oid='public.user_reports'::regclass) then raise exception 'user_reports must have RLS enabled'; end if;
 if has_table_privilege('authenticated','public.user_reports','SELECT') then raise exception 'users must not browse private reports'; end if;
 if not has_function_privilege('authenticated','public.report_user(uuid,text,text)','EXECUTE') then raise exception 'signed-in users must submit reports through guarded RPC'; end if;
 if has_function_privilege('anon','public.report_user(uuid,text,text)','EXECUTE') then raise exception 'anonymous users must not submit reports'; end if;
 if not has_function_privilege('authenticated','public.heartbeat_presence()','EXECUTE') then raise exception 'presence heartbeat missing'; end if;
 if not has_function_privilege('authenticated','public.conversation_peer_read_at(uuid)','EXECUTE') then raise exception 'read receipt lookup missing'; end if;
end; $$;