-- Identity, discovery, search visibility, blocking, admin allow-list, avatars.

-- Sign-up creates a profile ----------------------------------------------------
do $$
declare a uuid; c uuid; w uuid;
begin
  a := t.make_user('Ada Obi');
  perform t.eq((select display_name from public.profiles where id = a), 'Ada Obi', 'profile is created from the sign-up name');
  perform t.eq((select status from public.profiles where id = a), 'active', 'new accounts are active');
  perform t.ok((select onboarding_completed_at is null from public.profiles where id = a), 'new accounts have not finished onboarding');

  insert into auth.users (id, email, raw_user_meta_data)
  values (gen_random_uuid(), 'blank.name@example.test', '{"display_name":"   "}') returning id into c;
  perform t.eq((select display_name from public.profiles where id = c), 'blank.name', 'a blank name falls back to the email name');

  insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), null, '{}') returning id into w;
  perform t.eq((select display_name from public.profiles where id = w), 'New member', 'no name and no email still works');

  insert into auth.users (id, email, raw_user_meta_data)
  values (gen_random_uuid(), 'long@example.test', jsonb_build_object('display_name', repeat('x', 300))) returning id into w;
  perform t.eq((select char_length(display_name) from public.profiles where id = w)::bigint, 80, 'long names are cut to 80 characters');
end $$;

-- Editing your own profile, and nothing else ----------------------------------------
do $$
declare a uuid := t.make_user('Ada'); b uuid := t.make_user('Bola');
begin
  perform t.as_user(a);
  perform t.eq(t.affected(format('update public.profiles set bio = %L, display_name = %L where id = %L', 'Hello', 'Ada O.', a)), 1, 'users can edit their own name and bio');
  perform t.eq(t.affected(format('update public.profiles set bio = %L where id = %L', 'hacked', b)), 0, 'users cannot edit someone else (the row is invisible)');
  perform t.fails(format('update public.profiles set status = %L where id = %L', 'suspended', a), '42501', 'users cannot change their own status');
  perform t.fails(format('update public.profiles set onboarding_completed_at = now() where id = %L', a), '42501', 'users cannot mark themselves onboarded');
  perform t.fails(format('update public.profiles set id = %L where id = %L', gen_random_uuid(), a), '42501', 'users cannot change their id');
  perform t.fails(format('update public.profiles set username = %L where id = %L', 'Bad Name!', a), '23514', 'username format is enforced');
  perform t.fails(format('update public.profiles set timezone = %L where id = %L', 'Mars/Phobos', a), '23514', 'timezone must be real');
  perform t.fails(format('update public.profiles set bio = %L where id = %L', repeat('x', 501), a), '23514', 'bio length is limited');
  perform t.fails('insert into public.profiles (id, display_name) values (gen_random_uuid(), ''Fake'')', '42501', 'users cannot create profiles');
  perform t.fails(format('delete from public.profiles where id = %L', a), '42501', 'users cannot delete profiles');
  perform t.eq(t.affected(format('update public.profiles set username = %L where id = %L', 'ada_o', a)), 1, 'a valid username is accepted');
  perform t.reset();

  perform t.as_user(b);
  perform t.fails(format('update public.profiles set username = %L where id = %L', 'ada_o', b), '23505', 'usernames are unique');
  perform t.reset();
end $$;

-- Onboarding ---------------------------------------------------------------------------
do $$
declare a uuid := t.make_user('Newcomer');
begin
  perform t.as_user(a);
  perform t.fails('select public.complete_onboarding()', '23514', 'onboarding needs a username first');
  update public.profiles set username = 'newcomer_1' where id = a;
  perform t.ok(public.complete_onboarding() is not null, 'onboarding completes once a username exists');
  perform t.reset();

  perform t.as_anon();
  perform t.fails('select public.complete_onboarding()', '42501', 'visitors cannot call onboarding');
  perform t.reset();
end $$;

-- Who can see whom ------------------------------------------------------------------------
do $$
declare viewer uuid := t.make_member('Viewer'); fresh uuid := t.make_user('Not Onboarded');
        member uuid := t.make_member('Visible Member'); hidden uuid := t.make_member('Hidden Member');
        prov uuid := t.make_provider('Public Provider'); susp uuid := t.make_member('Suspended Member');
begin
  update public.profiles set is_discoverable = false where id = hidden;
  update public.profiles set status = 'suspended' where id = susp;

  perform t.as_user(viewer);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', viewer)), 1, 'you can always see yourself');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', member)), 1, 'onboarded, discoverable members are visible to signed-in people');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', prov)), 1, 'approved providers are visible');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', fresh)), 0, 'people who have not finished onboarding are invisible');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', hidden)), 0, 'people who opted out of discovery are invisible');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', susp)), 0, 'suspended accounts are invisible');
  perform t.reset();

  perform t.as_anon();
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', member)), 0, 'visitors cannot see ordinary members');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', prov)), 1, 'visitors can see approved providers');
  perform t.fails('select timezone from public.profiles', '42501', 'visitors cannot read timezone');
  perform t.fails('select country_code from public.profiles', '42501', 'visitors cannot read country');
  perform t.fails('select status from public.profiles', '42501', 'visitors cannot read account status');
  perform t.eq(t.rows('select id, username, display_name, avatar_path, bio, interests, expertise, accepts_free_chats from public.profiles'), 1, 'visitors can read the public card fields');
  perform t.reset();

  -- A provider who hides from discovery disappears for everyone.
  update public.profiles set is_discoverable = false where id = prov;
  perform t.as_anon();
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', prov)), 0, 'a provider who hid themselves is invisible to visitors');
  perform t.eq(t.rows(format('select user_id from public.provider_profiles where user_id = %L', prov)), 0, 'and so is their provider profile');
  perform t.reset();
  perform t.as_user(viewer);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', prov)), 0, 'and invisible to signed-in people');
  perform t.reset();
end $$;

-- Search ------------------------------------------------------------------------------------
do $$
declare viewer uuid := t.make_member('Searcher'); target uuid := t.make_member('Zanzibar Quill');
begin
  update public.profiles set username = 'quill_writer' where id = target;
  perform t.as_user(viewer);
  perform t.eq(t.rows($q$select id from public.profiles where username ilike '%quill%'$q$), 1, 'search finds people by username');
  perform t.eq(t.rows($q$select id from public.profiles where display_name ilike '%zanzibar%'$q$), 1, 'search finds people by name');
  perform t.fails('select email from auth.users', '42501', 'search cannot reach email addresses');
  perform t.reset();
end $$;

-- Blocking ------------------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Blocker'); b uuid := t.make_member('Blocked'); c uuid := t.make_member('Bystander');
        p uuid := t.make_provider('Blocking Provider');
begin
  perform t.as_user(a);
  insert into public.blocks (blocker_id, blocked_id) values (a, b);
  perform t.eq(t.rows('select * from public.blocks'), 1, 'the blocker sees their block');
  perform t.fails(format('insert into public.blocks (blocker_id, blocked_id) values (%L, %L)', b, a), '42501', 'you cannot block on someone else''s behalf');
  perform t.fails(format('insert into public.blocks (blocker_id, blocked_id) values (%L, %L)', a, a), '23514', 'you cannot block yourself');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', b)), 0, 'the blocker no longer sees the person they blocked');
  perform t.reset();

  perform t.as_user(b);
  perform t.eq(t.rows('select * from public.blocks'), 0, 'the blocked person cannot see that they were blocked');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', a)), 0, 'the blocked person no longer sees the blocker either');
  perform t.eq(t.affected(format('delete from public.blocks where blocker_id = %L', a)), 0, 'the blocked person cannot remove the block');
  perform t.reset();

  perform t.as_user(c);
  perform t.eq(t.rows(format('select id from public.profiles where id in (%L, %L)', a, b)), 2, 'other people are unaffected');
  perform t.reset();

  -- Blocking a provider hides them from search for the blocked person.
  insert into public.blocks (blocker_id, blocked_id) values (p, c);
  perform t.as_user(c);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', p)), 0, 'a blocked person cannot find the provider who blocked them');
  perform t.eq(t.rows(format('select user_id from public.provider_profiles where user_id = %L', p)), 0, 'nor their provider profile');
  perform t.reset();
  perform t.as_user(a);
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', p)), 1, 'everyone else still sees the provider');
  perform t.reset();

  perform t.as_user(a);
  perform t.eq(t.affected(format('delete from public.blocks where blocked_id = %L', b)), 1, 'the blocker can unblock');
  perform t.eq(t.rows(format('select id from public.profiles where id = %L', b)), 1, 'unblocking restores visibility');
  perform t.reset();
end $$;

-- Admin allow-list ----------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Regular'); adm uuid := t.make_member('Admin Person');
begin
  insert into public.admin_users (user_id) values (adm);

  perform t.as_user(a);
  perform t.fails('select * from public.admin_users', '42501', 'users cannot read the admin list');
  perform t.fails(format('insert into public.admin_users (user_id) values (%L)', a), '42501', 'users cannot make themselves admin');
  perform t.eq(t.val('select private.is_admin()'), 'false', 'a normal user is not an admin');
  perform t.reset();

  perform t.as_user(adm);
  perform t.eq(t.val('select private.is_admin()'), 'true', 'an allow-listed user is an admin');
  perform t.reset();

  perform t.as_anon();
  perform t.fails('select * from public.admin_users', '42501', 'visitors cannot read the admin list');
  perform t.reset();

  -- A token that merely CLAIMS to be an admin is ignored.
  perform set_config('request.jwt.claims',
    json_build_object('sub', a::text, 'role', 'authenticated',
                      'user_metadata', json_build_object('role', 'admin'),
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  execute 'set local role authenticated';
  perform t.eq(t.val('select private.is_admin()'), 'false', 'admin claims inside the token are ignored');
  perform t.reset();
end $$;

-- Avatar storage ---------------------------------------------------------------------------------
do $$
declare a uuid := t.make_member('Photo A'); b uuid := t.make_member('Photo B');
begin
  perform t.eq((select public::text from storage.buckets where id = 'avatars'), 'true', 'avatars bucket is public');
  perform t.eq((select file_size_limit::text from storage.buckets where id = 'avatars'), '2097152', 'avatar size limit is 2 MB');
  perform t.eq((select array_to_string(allowed_mime_types, ',') from storage.buckets where id = 'avatars'), 'image/jpeg,image/png,image/webp', 'only images are allowed');

  perform t.as_user(a);
  insert into storage.objects (bucket_id, name, owner) values ('avatars', a::text || '/me.png', a);
  perform t.fails(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)', 'avatars', b::text || '/me.png', a), '42501', 'users cannot upload into someone else''s folder');
  perform t.fails(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)', 'avatars', 'loose.png', a), '42501', 'uploads must be inside the owner''s folder');
  perform t.reset();

  insert into storage.objects (bucket_id, name, owner) values ('avatars', b::text || '/b.png', b);
  perform t.as_user(a);
  perform t.eq(t.rows('select * from storage.objects'), 1, 'a user only lists their own files');
  perform t.eq(t.affected(format('delete from storage.objects where name = %L', b::text || '/b.png')), 0, 'a user cannot delete another user''s file');
  perform t.eq(t.affected(format('delete from storage.objects where name = %L', a::text || '/me.png')), 1, 'a user can delete their own file');
  perform t.reset();

  perform t.as_anon();
  perform t.eq(t.rows('select * from storage.objects'), 0, 'visitors cannot list files through the API');
  perform t.reset();
end $$;
