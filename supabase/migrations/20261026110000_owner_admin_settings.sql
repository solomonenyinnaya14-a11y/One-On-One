-- Owner-only administration and private report moderation for One On One.
-- The first/oldest admin_users row is the permanent platform owner. Further admins
-- are created only through the owner-gated RPCs below.

create or replace function private.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users owner_row
    where owner_row.user_id = (select auth.uid())
      and owner_row.user_id = (
        select a.user_id from public.admin_users a
        order by a.granted_at asc, a.user_id asc limit 1
      )
  );
$$;

create or replace function public.am_i_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select private.is_platform_owner(); $$;
revoke all on function public.am_i_owner() from public, anon, authenticated;
grant execute on function public.am_i_owner() to authenticated, service_role;

create or replace function public.owner_list_admins()
returns table(user_id uuid, username text, display_name text, is_owner boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_owner() then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  return query
    select a.user_id, p.username, p.display_name,
      (a.user_id = (select x.user_id from public.admin_users x order by x.granted_at asc, x.user_id asc limit 1))
    from public.admin_users a join public.profiles p on p.id = a.user_id
    order by a.granted_at asc, a.user_id asc;
end;
$$;
revoke all on function public.owner_list_admins() from public, anon, authenticated;
grant execute on function public.owner_list_admins() to authenticated, service_role;

create or replace function public.owner_search_users(p_query text)
returns table(user_id uuid, username text, display_name text, is_admin boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_query text := lower(btrim(coalesce(p_query, '')));
begin
  if not private.is_platform_owner() then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  if char_length(v_query) < 2 or char_length(v_query) > 80 then
    raise exception 'invalid_search' using errcode = '22023';
  end if;
  return query
    select p.id, p.username, p.display_name,
      exists(select 1 from public.admin_users a where a.user_id = p.id)
    from public.profiles p
    where p.id <> (select auth.uid())
      and p.status = 'active'
      and (lower(coalesce(p.username,'')) like '%' || v_query || '%'
        or lower(p.display_name) like '%' || v_query || '%')
    order by (lower(coalesce(p.username,'')) = v_query) desc, p.display_name asc
    limit 25;
end;
$$;
revoke all on function public.owner_search_users(text) from public, anon, authenticated;
grant execute on function public.owner_search_users(text) to authenticated, service_role;

create or replace function public.owner_grant_admin(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_owner() then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  if p_user is null or p_user = (select auth.uid()) then
    raise exception 'invalid_admin_target' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user and p.status = 'active') then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  insert into public.admin_users(user_id, granted_by)
  values (p_user, (select auth.uid()))
  on conflict (user_id) do nothing;
end;
$$;
revoke all on function public.owner_grant_admin(uuid) from public, anon, authenticated;
grant execute on function public.owner_grant_admin(uuid) to authenticated, service_role;

create or replace function public.owner_revoke_admin(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_owner() then
    raise exception 'owner_only' using errcode = '42501';
  end if;
  if p_user is null or p_user = (select auth.uid()) then
    raise exception 'owner_cannot_be_removed' using errcode = '42501';
  end if;
  delete from public.admin_users a
  where a.user_id = p_user
    and a.user_id <> (
      select x.user_id from public.admin_users x
      order by x.granted_at asc, x.user_id asc limit 1
    );
  if not found then
    raise exception 'admin_not_found_or_owner' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.owner_revoke_admin(uuid) from public, anon, authenticated;
grant execute on function public.owner_revoke_admin(uuid) to authenticated, service_role;

create or replace function public.admin_list_reports()
returns table(
  report_id uuid, reporter_id uuid, reporter_username text, reporter_display_name text,
  reported_user_id uuid, reported_username text, reported_display_name text,
  reason text, details text, status text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  return query
    select r.id, r.reporter_id, reporter.username, reporter.display_name,
      r.reported_user_id, reported.username, reported.display_name,
      r.reason, r.details, r.status, r.created_at
    from public.user_reports r
    join public.profiles reporter on reporter.id = r.reporter_id
    join public.profiles reported on reported.id = r.reported_user_id
    order by case r.status when 'open' then 0 when 'reviewing' then 1 else 2 end, r.created_at desc
    limit 200;
end;
$$;
revoke all on function public.admin_list_reports() from public, anon, authenticated;
grant execute on function public.admin_list_reports() to authenticated, service_role;

create or replace function public.admin_update_report_status(p_report uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  if p_status not in ('reviewing','resolved','dismissed') then
    raise exception 'invalid_report_status' using errcode = '22023';
  end if;
  update public.user_reports set status = p_status where id = p_report;
  if not found then
    raise exception 'report_not_found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.admin_update_report_status(uuid,text) from public, anon, authenticated;
grant execute on function public.admin_update_report_status(uuid,text) to authenticated, service_role;
