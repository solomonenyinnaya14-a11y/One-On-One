-- Analytics and report-moderation regression tests.
do $$
declare
  owner_id uuid := t.make_member('Analytics Owner');
  reporter_id uuid := t.make_member('Analytics Reporter');
  reported_id uuid := t.make_member('Analytics Reported');
  report_id uuid;
  snapshot jsonb;
begin
  insert into public.admin_users(user_id, granted_by) values(owner_id, owner_id);
  perform t.as_user(reporter_id);
  report_id := public.report_user(reported_id, 'harassment', 'Please review this report');
  perform t.ok(report_id is not null, 'signed-in user can submit a report through the guarded RPC');
  perform t.fails(format('select * from public.admin_list_reports()'), '42501', 'ordinary user cannot list reports');
  perform t.fails('select public.admin_analytics_snapshot()', '42501', 'ordinary user cannot read analytics');
  perform t.reset();

  perform t.as_user(owner_id);
  perform t.ok(public.am_i_admin(), 'platform owner is an admin');
  perform t.eq(t.rows(format('select * from public.admin_list_reports() where report_id = %L', report_id)), 1, 'admin sees submitted report');
  perform public.admin_update_report_status(report_id, 'reviewing');
  perform t.eq((select status from public.user_reports where id = report_id), 'reviewing', 'admin can update moderation status');
  snapshot := public.admin_analytics_snapshot();
  perform t.ok(snapshot ? 'totalUsers', 'analytics includes total users');
  perform t.ok(snapshot ? 'seenUsers7d', 'analytics includes recent presence');
  perform t.ok(snapshot ? 'voiceMessages', 'analytics includes voice message counts');
  perform t.ok(snapshot ? 'openReports', 'analytics includes moderation queue counts');
  perform t.ok(jsonb_typeof(snapshot->'daily') = 'array', 'analytics includes daily trend data');
  perform t.reset();

  perform t.ok(not has_function_privilege('anon', 'public.admin_analytics_snapshot()', 'EXECUTE'), 'anonymous users cannot execute analytics RPC');
  perform t.ok(not has_table_privilege('authenticated', 'public.user_reports', 'SELECT'), 'users cannot directly browse report records');
end $$;
