-- Safety, presence, and WhatsApp-style read receipts for the messaging-first MVP.
set search_path = public, extensions;
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists show_online_status boolean not null default true;
grant update (show_online_status) on public.profiles to authenticated;
create or replace function public.heartbeat_presence()
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_seen timestamptz := now();
begin
 if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
 update public.profiles set last_seen_at = case when show_online_status then v_seen else null end where id=v_uid and status='active';
 return v_seen;
end; $$;
revoke all on function public.heartbeat_presence() from public, anon, authenticated;
grant execute on function public.heartbeat_presence() to authenticated, service_role;
create table if not exists public.user_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete restrict,
 reported_user_id uuid not null references public.profiles(id) on delete restrict,
 reason text not null check (reason in ('spam','harassment','impersonation','inappropriate','scam','other')),
 details text,
 status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
 created_at timestamptz not null default now(),
 constraint user_reports_not_self check (reporter_id <> reported_user_id),
 constraint user_reports_details_length check (details is null or char_length(details) <= 1000)
);
create index if not exists user_reports_open_created_idx on public.user_reports(status, created_at desc);
alter table public.user_reports enable row level security;
revoke all on public.user_reports from anon, authenticated;
create or replace function public.report_user(p_reported_user uuid, p_reason text, p_details text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
 if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
 if p_reported_user is null or p_reported_user=v_uid then raise exception 'invalid_report_target' using errcode = '22023'; end if;
 if p_reason not in ('spam','harassment','impersonation','inappropriate','scam','other') then raise exception 'invalid_report_reason' using errcode = '22023'; end if;
 if p_details is not null and char_length(p_details)>1000 then raise exception 'report_details_too_long' using errcode = '22023'; end if;
 if not exists(select 1 from public.profiles p where p.id=p_reported_user and p.status='active') then raise exception 'report_target_unavailable' using errcode = 'P0002'; end if;
 if (select count(*) from public.user_reports r where r.reporter_id=v_uid and r.created_at>now()-interval '24 hours')>=10 then raise exception 'report_rate_limited' using errcode = '54000'; end if;
 insert into public.user_reports(reporter_id,reported_user_id,reason,details) values(v_uid,p_reported_user,p_reason,nullif(btrim(p_details),'')) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.report_user(uuid,text,text) from public, anon, authenticated;
grant execute on function public.report_user(uuid,text,text) to authenticated, service_role;
create or replace function public.conversation_peer_read_at(p_conversation uuid)
returns timestamptz language plpgsql security definer stable set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_peer uuid; v_read timestamptz;
begin
 if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
 select case when c.user_a=v_uid then c.user_b else c.user_a end into v_peer
 from public.conversations c where c.id=p_conversation and v_uid in (c.user_a,c.user_b);
 if v_peer is null then raise exception 'conversation_not_allowed' using errcode = '42501'; end if;
 select r.last_read_at into v_read from public.conversation_reads r where r.conversation_id=p_conversation and r.user_id=v_peer;
 return v_read;
end; $$;
revoke all on function public.conversation_peer_read_at(uuid) from public, anon, authenticated;
grant execute on function public.conversation_peer_read_at(uuid) to authenticated, service_role;