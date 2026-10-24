-- Provider applications: submit, admin review, and what the public sees.

do $$
declare
  admin uuid := t.make_member('Admin Person');
  applicant uuid := t.make_member('Applicant One');
  other uuid := t.make_member('Applicant Two');
  topic uuid := (select id from public.topics where slug = 'career');
  o uuid;
begin
  insert into public.admin_users (user_id) values (admin);

  -- Apply: a draft profile, then submit it.
  perform t.as_user(applicant);
  insert into public.provider_profiles (user_id, headline, about) values (applicant, 'Career coach', 'I help people plan moves.');
  insert into public.provider_topics (provider_id, topic_id) values (applicant, topic);
  perform t.fails(format('update public.provider_profiles set status = %L where user_id = %L', 'approved', applicant), '42501', 'applicants cannot approve themselves');
  perform t.eq(t.affected(format('update public.provider_profiles set status = %L where user_id = %L', 'pending_review', applicant)), 1, 'submitting works');
  perform t.fails(format('select public.admin_review_provider(%L, true)', applicant), '42501', 'only admins can review');
  perform t.reset();

  -- A pending applicant is not public and cannot be discovered as a provider.
  perform t.as_user(other);
  perform t.eq(t.rows(format('select 1 from public.provider_profiles where user_id = %L', applicant)), 0, 'pending providers are invisible to others');
  perform t.reset();

  -- A pending provider can create an offering (their free one) but it is not bookable.
  perform t.as_user(applicant);
  o := public.create_offering('text', 'Career chat', 'One conversation', 30, 500000, topic);
  perform t.reset();
  perform t.ok(not private.offering_accepts_bookings(o), 'offering is not bookable before approval');

  -- Admin review.
  perform t.as_user(admin);
  perform t.ok(public.am_i_admin(), 'admin is recognised');
  perform t.fails(format('select public.admin_review_provider(%L, false)', applicant), '22023', 'rejection needs a reason');
  perform t.eq(public.admin_review_provider(applicant, true), 'approved', 'approval works');
  perform t.fails(format('select public.admin_review_provider(%L, true)', applicant), '23514', 'cannot review twice');
  perform t.fails(format('select public.admin_review_provider(%L, true)', gen_random_uuid()), 'P0002', 'unknown provider');
  perform t.reset();

  perform t.as_user(other);
  perform t.ok(not public.am_i_admin(), 'non-admin is not admin');
  perform t.eq(t.rows(format('select 1 from public.provider_profiles where user_id = %L', applicant)), 1, 'approved providers are public');
  perform t.eq(t.rows(format('select 1 from public.offerings where id = %L', o)), 1, 'their offering is now listed');
  perform t.reset();
  perform t.ok(private.offering_accepts_bookings(o), 'offering is bookable after approval');
  perform t.ok((select reviewed_by from public.provider_profiles where user_id = applicant) = admin, 'reviewer is recorded');

  -- Rejection path: reason is kept and the applicant can fix and resubmit.
  perform t.as_user(other);
  insert into public.provider_profiles (user_id, headline, about) values (other, 'Tutor', 'Maths help.');
  update public.provider_profiles set status = 'pending_review' where user_id = other;
  perform t.reset();
  perform t.as_user(admin);
  perform t.eq(public.admin_review_provider(other, false, 'Please add more detail'), 'rejected', 'rejection works');
  perform t.reset();
  perform t.as_user(other);
  perform t.eq((select rejection_reason from public.provider_profiles where user_id = other), 'Please add more detail', 'applicant sees the reason');
  perform t.eq(t.affected(format('update public.provider_profiles set status = %L where user_id = %L', 'pending_review', other)), 1, 'can resubmit after rejection');
  perform t.reset();
end $$;
