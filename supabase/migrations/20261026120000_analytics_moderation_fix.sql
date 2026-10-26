-- Repair report moderation and add owner/admin usage analytics.
-- Additive only: no user content is altered or deleted.
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists show_online_status boolean not null default true;

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
create index if not exists user_reports_status_created_idx on public.user_reports(status, created_at desc);
create index if not exists user_reports_reporter_created_idx on public.user_reports(reporter_id, created_at desc);
alter table public.user_reports enable row level security;
revoke all on public.user_reports from public, anon, authenticated;

create or replace function public.report_user(p_reported_user uuid, p_reason text, p_details text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_reason text := lower(btrim(coalesce(p_reason,'')));
  v_details text := nullif(btrim(coalesce(p_details,'')), '');
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_reported_user is null or p_reported_user = v_uid then raise exception 'invalid_report_target' using errcode = '22023'; end if;
  if v_reason not in ('spam','harassment','impersonation','inappropriate','scam','other') then raise exception 'invalid_report_reason' using errcode = '22023'; end if;
  if v_details is not null and char_length(v_details) > 1000 then raise exception 'report_details_too_long' using errcode = '22023'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_reported_user and p.status = 'active') then raise exception 'report_target_unavailable' using errcode = 'P0002'; end if;
  if (select count(*) from public.user_reports r where r.reporter_id = v_uid and r.created_at > now() - interval '24 hours') >= 10 then raise exception 'report_rate_limited' using errcode = '54000'; end if;
  insert into public.user_reports(reporter_id, reported_user_id, reason, details) values (v_uid, p_reported_user, v_reason, v_details) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.report_user(uuid,text,text) from public, anon, authenticated;
grant execute on function public.report_user(uuid,text,text) to authenticated, service_role;

create or replace function public.admin_list_reports()
returns table(report_id uuid, reporter_id uuid, reporter_username text, reporter_display_name text, reported_user_id uuid, reported_username text, reported_display_name text, reason text, details text, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  return query
    select r.id, r.reporter_id, reporter.username, reporter.display_name, r.reported_user_id, reported.username, reported.display_name, r.reason, r.details, r.status, r.created_at
    from public.user_reports r
    left join public.profiles reporter on reporter.id = r.reporter_id
    left join public.profiles reported on reported.id = r.reported_user_id
    order by case r.status when 'open' then 0 when 'reviewing' then 1 else 2 end, r.created_at desc
    limit 200;
end;
$$;
revoke all on function public.admin_list_reports() from public, anon, authenticated;
grant execute on function public.admin_list_reports() to authenticated, service_role;

create or replace function public.admin_update_report_status(p_report uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not private.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  if p_report is null or p_status not in ('reviewing','resolved','dismissed') then raise exception 'invalid_report_status' using errcode = '22023'; end if;
  update public.user_reports set status = p_status where id = p_report;
  if not found then raise exception 'report_not_found' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function public.admin_update_report_status(uuid,text) from public, anon, authenticated;
grant execute on function public.admin_update_report_status(uuid,text) to authenticated, service_role;

create or replace function public.admin_analytics_snapshot()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb;
begin
  if not private.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  select jsonb_build_object(
    'totalUsers', (select count(*) from public.profiles),
    'activeUsers', (select count(*) from public.profiles where status = 'active'),
    'newUsers7d', (select count(*) from public.profiles where created_at >= now() - interval '7 days'),
    'newUsers30d', (select count(*) from public.profiles where created_at >= now() - interval '30 days'),
    'seenUsers7d', (select count(*) from public.profiles where last_seen_at >= now() - interval '7 days'),
    'seenUsers30d', (select count(*) from public.profiles where last_seen_at >= now() - interval '30 days'),
    'totalConversations', (select count(*) from public.conversations),
    'activeConversations', (select count(*) from public.conversations where status = 'active'),
    'pendingRequests', (select count(*) from public.conversations where status = 'request'),
    'conversations7d', (select count(*) from public.conversations where created_at >= now() - interval '7 days'),
    'totalMessages', (select count(*) from public.messages where kind in ('user','voice')),
    'textMessages', (select count(*) from public.messages where kind = 'user'),
    'voiceMessages', (select count(*) from public.messages where kind = 'voice'),
    'messages7d', (select count(*) from public.messages where kind in ('user','voice') and created_at >= now() - interval '7 days'),
    'openReports', (select count(*) from public.user_reports where status = 'open'),
    'reviewingReports', (select count(*) from public.user_reports where status = 'reviewing'),
    'resolvedReports', (select count(*) from public.user_reports where status = 'resolved'),
    'dismissedReports', (select count(*) from public.user_reports where status = 'dismissed'),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object(
      'date', d.day::date,
      'newUsers', (select count(*) from public.profiles p where p.created_at >= d.day and p.created_at < d.day + interval '1 day'),
      'messages', (select count(*) from public.messages m where m.kind in ('user','voice') and m.created_at >= d.day and m.created_at < d.day + interval '1 day'),
      'conversations', (select count(*) from public.conversations c where c.created_at >= d.day and c.created_at < d.day + interval '1 day')
    ) order by d.day), '[]'::jsonb) from generate_series(date_trunc('day', now()) - interval '6 days', date_trunc('day', now()), interval '1 day') as d(day))
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.admin_analytics_snapshot() from public, anon, authenticated;
grant execute on function public.admin_analytics_snapshot() to authenticated, service_role;
