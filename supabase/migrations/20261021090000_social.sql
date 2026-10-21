-- One On One migration 09: following.
--
-- People can follow each other. Follows are written only through follow_user() /
-- unfollow_user(), which apply the same visibility and blocking rules as discovery.
-- Counts are returned by profile_stats() and only for profiles the caller may see.
-- Nobody can list another person's followers or following.

set search_path = public, extensions;

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint follows_not_self check (follower_id <> followee_id)
);

create index follows_followee_id_idx on public.follows (followee_id);

alter table public.follows enable row level security;
revoke all on public.follows from anon, authenticated;
-- Read-only through the API, and only your own outgoing follows.
grant select on public.follows to authenticated;

create policy follows_select_own on public.follows
  for select to authenticated
  using (follower_id = (select auth.uid()));

-- Can the signed-in caller see this person's profile? Mirrors the profile
-- policies (own profile, discoverable member, public provider, not blocked).
create function private.can_view_profile(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user = (select auth.uid())
      or exists (
        select 1
          from public.profiles p
         where p.id = p_user
           and p.status = 'active'
           and p.is_discoverable
           and p.username is not null
           and p.onboarding_completed_at is not null
           and not private.is_blocked_between((select auth.uid()), p_user)
      );
$$;

create function public.follow_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_following integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_target is null or p_target = v_uid then
    raise exception 'invalid_target' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles p
     where p.id = v_uid and p.status = 'active' and p.onboarding_completed_at is not null
  ) then
    raise exception 'account_not_active' using errcode = '42501';
  end if;
  -- Hidden, blocked and unknown people all look the same from outside.
  if not private.can_view_profile(p_target) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  select count(*) into v_following from public.follows f where f.follower_id = v_uid;
  if v_following >= 2000 then
    raise exception 'too_many_follows' using errcode = '54000';
  end if;

  insert into public.follows (follower_id, followee_id)
  values (v_uid, p_target)
  on conflict do nothing;
end;
$$;

create function public.unfollow_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from public.follows f where f.follower_id = v_uid and f.followee_id = p_target;
end;
$$;

-- Counts for a profile the caller is allowed to see. Returns no row otherwise.
create function public.profile_stats(p_user uuid)
returns table (follower_count bigint, following_count bigint, viewer_follows boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from public.follows f
       join public.profiles pf on pf.id = f.follower_id and pf.status = 'active'
      where f.followee_id = p_user),
    (select count(*) from public.follows f
       join public.profiles pt on pt.id = f.followee_id and pt.status = 'active'
      where f.follower_id = p_user),
    exists (select 1 from public.follows f
             where f.follower_id = (select auth.uid()) and f.followee_id = p_user)
   where (select auth.uid()) is not null
     and (private.can_view_profile(p_user) or private.is_public_provider(p_user));
$$;

revoke all on function public.follow_user(uuid), public.unfollow_user(uuid), public.profile_stats(uuid)
  from public, anon, authenticated;
grant execute on function public.follow_user(uuid), public.unfollow_user(uuid), public.profile_stats(uuid)
  to authenticated, service_role;

-- Blocking someone ends any follow in either direction.
create function private.drop_follows_on_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows f
   where (f.follower_id = new.blocker_id and f.followee_id = new.blocked_id)
      or (f.follower_id = new.blocked_id and f.followee_id = new.blocker_id);
  return new;
end;
$$;

create trigger blocks_drop_follows
  after insert on public.blocks
  for each row execute function private.drop_follows_on_block();
