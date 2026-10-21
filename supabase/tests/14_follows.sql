-- Following: visibility rules, blocking, counts and what cannot be written directly.

select t.reset_settings();

do $$
declare a uuid := t.make_member('Follow A'); b uuid := t.make_member('Follow B');
        hidden uuid := t.make_member('Follow Hidden'); raw uuid := t.make_user('Follow Raw');
        prov uuid := t.make_provider('Follow Provider'); n bigint;
begin
  update public.profiles set is_discoverable = false where id = hidden;

  perform t.as_user(a);
  perform public.follow_user(b);
  perform public.follow_user(b);
  perform t.eq(t.rows('select * from public.follows'), 1, 'following twice leaves one follow');
  perform public.follow_user(prov);
  perform t.fails(format('select public.follow_user(%L)', a), '22023', 'you cannot follow yourself');
  perform t.fails(format('select public.follow_user(%L)', hidden), 'P0002', 'a hidden profile cannot be followed');
  perform t.fails(format('select public.follow_user(%L)', raw), 'P0002', 'someone who has not finished onboarding cannot be followed');
  perform t.fails(format('select public.follow_user(%L)', gen_random_uuid()), 'P0002', 'an unknown id cannot be followed');
  perform t.fails(format('insert into public.follows (follower_id, followee_id) values (%L, %L)', a, hidden), '42501', 'direct inserts are refused');
  perform t.fails(format('delete from public.follows where follower_id = %L', a), '42501', 'direct deletes are refused');
  perform t.eq((select follower_count from public.profile_stats(b)), 1, 'B has one follower');
  perform t.eq((select following_count from public.profile_stats(a)), 2, 'A follows two people');
  perform t.ok((select viewer_follows from public.profile_stats(b)), 'A is shown as following B');
  perform t.eq(t.rows(format('select * from public.profile_stats(%L)', hidden)), 0, 'stats for a hidden profile are not returned');
  perform t.reset();

  perform t.as_user(b);
  perform t.eq(t.rows('select * from public.follows'), 0, 'B cannot see who follows them, only their own follows');
  perform t.ok(not (select viewer_follows from public.profile_stats(a)), 'B does not follow A');
  perform t.eq((select follower_count from public.profile_stats(b)), 1, 'B sees their own follower count');
  perform public.unfollow_user(a);
  perform t.reset();

  perform t.as_anon();
  perform t.fails(format('select public.follow_user(%L)', b), '42501', 'visitors cannot follow');
  perform t.fails('select * from public.follows', '42501', 'visitors cannot read follows');
  perform t.reset();

  perform t.as_user(raw);
  perform t.fails(format('select public.follow_user(%L)', b), '42501', 'accounts that have not finished onboarding cannot follow');
  perform t.reset();

  perform t.as_user(a);
  perform public.unfollow_user(b);
  perform t.eq((select follower_count from public.profile_stats(b)), 0, 'unfollowing removes the follower');
  perform t.reset();
end $$;

do $$
declare a uuid := t.make_member('Block A'); b uuid := t.make_member('Block B');
begin
  perform t.as_user(a); perform public.follow_user(b); perform t.reset();
  perform t.as_user(b); perform public.follow_user(a); perform t.reset();
  perform t.eq((select count(*) from public.follows where follower_id in (a, b)), 2, 'both follow each other');

  perform t.as_user(a);
  insert into public.blocks (blocker_id, blocked_id) values (a, b);
  perform t.reset();
  perform t.eq((select count(*) from public.follows where follower_id in (a, b)), 0, 'blocking removes follows in both directions');

  perform t.as_user(b);
  perform t.fails(format('select public.follow_user(%L)', a), 'P0002', 'a blocked person cannot follow the blocker');
  perform t.reset();
  perform t.as_user(a);
  perform t.fails(format('select public.follow_user(%L)', b), 'P0002', 'the blocker cannot follow the blocked person');
  perform t.reset();
end $$;

do $$
declare a uuid := t.make_member('Susp A'); b uuid := t.make_member('Susp B');
begin
  perform t.as_user(a); perform public.follow_user(b); perform t.reset();
  update public.profiles set status = 'suspended' where id = a;
  perform t.as_user(b);
  perform t.eq((select follower_count from public.profile_stats(b)), 0, 'a suspended account is not counted as a follower');
  perform t.reset();
  perform t.as_user(a);
  perform t.fails(format('select public.follow_user(%L)', b), '42501', 'a suspended account cannot follow');
  perform t.reset();
end $$;
