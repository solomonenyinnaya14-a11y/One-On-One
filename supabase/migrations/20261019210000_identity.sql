-- One On One migration 1/7: identity.
--
-- Creates: the private helper schema, profiles, the admin allow-list, blocks,
-- and the avatars storage bucket with its policies.
--
-- Security model used by every migration in this folder:
--   * Every table has Row Level Security enabled.
--   * API roles (anon, authenticated) start with NO privileges; each table
--     grants back only the columns and operations that are needed.
--   * Anything involving money, status changes or other people's data is done
--     by SECURITY DEFINER functions or by the server using the service role,
--     never by direct client writes.
--   * The `private` schema holds helper functions used by policies. It must
--     NOT be added to the API's exposed schemas.

set search_path = public, extensions;

create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

-- Shared helpers -------------------------------------------------------------

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function private.is_valid_timezone(p_tz text)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_tz is null then
    return false;
  end if;
  perform now() at time zone p_tz;
  return true;
exception when others then
  return false;
end;
$$;

-- Admin allow-list -----------------------------------------------------------
-- Admins are added by hand with the service role (see docs/database.md). There
-- are deliberately no policies: no API role can read or write this table.

create table public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users (id) on delete set null
);

alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;

create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users a where a.user_id = (select auth.uid())
  );
$$;

-- Profiles -------------------------------------------------------------------
-- One row per account, created automatically at sign-up. Contains no email,
-- phone or payment data; those stay in auth.users or with the payment gateway.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text,
  display_name text not null,
  avatar_path text,
  bio text,
  timezone text not null default 'Africa/Lagos',
  country_code text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_key unique (username),
  constraint profiles_username_format check (username is null or username ~ '^[a-z0-9_]{3,30}$'),
  constraint profiles_display_name_length check (char_length(btrim(display_name)) between 1 and 80),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 500),
  constraint profiles_avatar_path_length check (avatar_path is null or char_length(avatar_path) <= 300),
  constraint profiles_country_format check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  constraint profiles_timezone_valid check (private.is_valid_timezone(timezone)),
  constraint profiles_status_valid check (status in ('active', 'suspended'))
);

create index profiles_display_name_trgm_idx
  on public.profiles using gin (display_name extensions.gin_trgm_ops);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- Creates the profile when someone signs up. The display name comes from the
-- sign-up form (user-supplied, length-limited) or falls back to the email name.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := nullif(btrim(coalesce(
    new.raw_user_meta_data ->> 'display_name',
    split_part(coalesce(new.email, ''), '@', 1)
  )), '');

  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(v_name, 'New member'), 80));

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to anon, authenticated;
-- Users may edit only these columns. id and status cannot be changed by them:
-- status (active/suspended) is a moderation decision made by the server.
grant update (username, display_name, avatar_path, bio, timezone, country_code)
  on public.profiles to authenticated;

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_select_admin on public.profiles
  for select to authenticated
  using ((select private.is_admin()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Blocks ---------------------------------------------------------------------
-- A user can block another user. The blocked person cannot see that they have
-- been blocked: only the blocker can read their own rows.

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);

create index blocks_blocked_id_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;
revoke all on public.blocks from anon, authenticated;
grant select, insert, delete on public.blocks to authenticated;

create policy blocks_select_own on public.blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy blocks_insert_own on public.blocks
  for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy blocks_delete_own on public.blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- True when either user has blocked the other. SECURITY DEFINER so that policies
-- and functions can check it without exposing the blocks table.
create function private.is_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b)
       or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

-- Avatars (storage) ----------------------------------------------------------
-- Public bucket (profile photos are shown on public provider pages). Files must
-- live in a folder named after the owner's user id: avatars/<user_id>/<file>.
-- Size and type limits are enforced by the bucket itself.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy avatars_select_own_folder on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_insert_own_folder on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_update_own_folder on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy avatars_delete_own_folder on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
