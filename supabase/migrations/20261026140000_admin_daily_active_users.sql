-- Add an explicit daily-active-users metric to the admin analytics snapshot.
create or replace function public.admin_daily_active_users()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  return (
    select count(*)::bigint
    from public.profiles p
    where p.status = 'active'
      and p.last_seen_at >= now() - interval '24 hours'
  );
end;
$$;
revoke all on function public.admin_daily_active_users() from public, anon, authenticated;
grant execute on function public.admin_daily_active_users() to authenticated, service_role;
