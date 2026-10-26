-- Owner-only administrator management and report moderation.
do $$
declare
  owner_id uuid := t.make_member('Platform Owner');
  admin_id uuid := t.make_member('Moderator');
  regular_id uuid := t.make_member('Regular Member');
  reported_id uuid := t.make_member('Reported Member');
  report_id uuid;
begin
  -- Earlier provider-review tests leave a temporary admin behind; isolate this
  -- owner-first test by clearing only test-fixture administrator rows.
  delete from public.admin_users;
  insert into public.admin_users(user_id) values(owner_id);
  perform t.as_user(owner_id);
  perform t.ok(public.am_i_owner(), 'first admin is platform owner');
  perform t.eq(t.rows(format('select * from public.owner_list_admins')), 1, 'owner sees their admin list');
  perform public.owner_grant_admin(admin_id);
  perform t.eq(t.rows(format('select * from public.owner_list_admins')), 2, 'owner sees added admin');
  perform t.reset();

  perform t.as_user(admin_id);
  perform t.ok(public.am_i_admin(), 'delegated admin is recognised');
  perform t.ok(not public.am_i_owner(), 'delegated admin is not owner');
  perform t.fails(format('select public.owner_grant_admin(%L)', regular_id), '42501', 'admin cannot grant admins');
  perform t.fails('select * from public.owner_list_admins()', '42501', 'admin cannot view admin roster');
  perform t.fails(format('select public.owner_revoke_admin(%L)', owner_id), '42501', 'admin cannot revoke owner');
  perform t.reset();

  perform t.as_user(regular_id);
  perform t.ok(not public.am_i_admin(), 'regular user is not admin');
  perform t.ok(not public.am_i_owner(), 'regular user is not owner');
  perform t.fails('select * from public.admin_list_reports()', '42501', 'regular user cannot read reports');
  perform t.fails(format('select public.admin_update_report_status(%L,%L)', gen_random_uuid(), 'resolved'), '42501', 'regular user cannot update reports');
  perform t.fails(format('select public.owner_grant_admin(%L)', admin_id), '42501', 'regular user cannot grant admins');
  perform t.reset();

  perform t.as_user(owner_id);
  perform public.owner_revoke_admin(admin_id);
  perform t.reset();
  perform t.ok(not exists(select 1 from public.admin_users where user_id=admin_id), 'owner revoked delegated admin');
  perform t.ok(exists(select 1 from public.admin_users where user_id=owner_id), 'owner remains registered');

  perform t.as_user(regular_id);
  report_id := public.report_user(reported_id, 'spam', 'Test report details');
  perform t.reset();
  perform t.as_user(owner_id);
  perform t.eq(t.rows(format('select * from public.admin_list_reports() where report_id = %L', report_id)), 1, 'owner can inspect reports');
  perform public.admin_update_report_status(report_id, 'reviewing');
  perform t.eq((select status from public.user_reports where id=report_id), 'reviewing', 'admin can update report status');
  perform t.reset();
end $$;
