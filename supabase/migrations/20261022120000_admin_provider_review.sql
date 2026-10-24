-- One On One migration 09: manual review of provider applications.
--
-- Providers submit their profile (draft -> pending_review) themselves, but only an
-- admin can approve or reject it, because approval is what makes a provider and
-- their offerings public. Until now that move could only be made with the service
-- role; this adds a narrow, audited function for admins instead of handing out
-- broader table access.

set search_path = public, extensions;

-- Lets the app decide whether to show the admin screens. Says nothing about
-- anyone else: it only ever answers for the caller.
create function public.am_i_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin();
$$;

revoke all on function public.am_i_admin() from public, anon, authenticated;
grant execute on function public.am_i_admin() to authenticated, service_role;

create function public.admin_review_provider(p_user uuid, p_approve boolean, p_reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_status text;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  if p_approve is null then
    raise exception 'decision_required' using errcode = '22023';
  end if;
  if not p_approve and v_reason is null then
    raise exception 'rejection_reason_required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 1000 then
    raise exception 'reason_too_long' using errcode = '22023';
  end if;

  select pp.status into v_status from public.provider_profiles pp where pp.user_id = p_user for update;
  if not found then
    raise exception 'provider_not_found' using errcode = 'P0002';
  end if;
  if v_status <> 'pending_review' then
    raise exception 'not_pending_review' using errcode = '23514';
  end if;

  update public.provider_profiles
     set status = case when p_approve then 'approved' else 'rejected' end,
         rejection_reason = case when p_approve then null else v_reason end,
         reviewed_by = v_uid
   where user_id = p_user;

  return case when p_approve then 'approved' else 'rejected' end;
end;
$$;

revoke all on function public.admin_review_provider(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_review_provider(uuid, boolean, text) to authenticated, service_role;
