-- =========================================================
-- Amazing Church Philippines — Supabase schema (idempotent)
-- Safe to re-run on an existing project — no data is lost.
-- Paste this whole file into Supabase → SQL Editor → Run.
-- =========================================================

-- ---------- Enums ----------
do $$ begin
  create type user_role as enum ('super_admin', 'admin', 'moderator', 'user');
exception when duplicate_object then null; end $$;

do $$ begin
  create type approval_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

-- ---------- Tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role user_role not null default 'user',
  account_status approval_status not null default 'pending',
  avatar_url text,
  contact_number text,
  leader_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists contact_number text;
alter table public.profiles add column if not exists leader_id uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists is_leader boolean not null default false;
create index if not exists profiles_leader_idx on public.profiles(leader_id);
create index if not exists profiles_is_leader_idx on public.profiles(is_leader);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  body text not null,
  media_url text,
  status approval_status not null default 'approved',
  moderated_by uuid references public.profiles(id),
  moderated_at timestamptz,
  created_at timestamptz not null default now()
);
-- If the table pre-existed with default 'pending', flip it now
alter table public.posts alter column status set default 'approved';
create index if not exists posts_status_created_idx on public.posts (status, created_at desc);

create table if not exists public.discussions (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  status approval_status not null default 'pending',
  moderated_by uuid references public.profiles(id),
  moderated_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists discussions_status_created_idx on public.discussions (status, created_at desc);

-- Unified comments (works for both posts and discussions)
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('post','discussion')),
  entity_id uuid not null,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists comments_entity_idx on public.comments (entity_type, entity_id, created_at);

-- Unified reactions (emoji-based)
create table if not exists public.reactions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('post','discussion')),
  entity_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 8),
  created_at timestamptz not null default now(),
  unique (entity_type, entity_id, user_id, emoji)
);
create index if not exists reactions_entity_idx on public.reactions (entity_type, entity_id);

-- Legacy table cleanup (safe: was never wired to a UI)
drop table if exists public.discussion_comments;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  cover_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- Bible verses are now fetched live from bible-api.com; local table no longer needed.
drop table if exists public.bible_verses;

create table if not exists public.live_videos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  video_url text not null,
  occurred_on date not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists live_videos_occurred_idx on public.live_videos (occurred_on desc);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists messages_recipient_idx on public.messages (recipient_id, created_at desc);

-- ---------- Helper functions ----------
create or replace function public.current_role() returns user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('super_admin','admin','moderator')
       from public.profiles where id = auth.uid()),
    false);
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('super_admin','admin')
       from public.profiles where id = auth.uid()),
    false);
$$;

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select account_status = 'approved' from public.profiles where id = auth.uid()),
    false);
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.discussions enable row level security;
alter table public.comments enable row level security;
alter table public.reactions enable row level security;
alter table public.events enable row level security;
alter table public.live_videos enable row level security;
alter table public.messages enable row level security;

drop policy if exists "everyone reads live videos" on public.live_videos;
create policy "everyone reads live videos" on public.live_videos
  for select using (true);

drop policy if exists "admins manage live videos" on public.live_videos;
drop policy if exists "staff manage live videos" on public.live_videos;
create policy "staff manage live videos" on public.live_videos
  for all using (public.is_staff()) with check (public.is_staff());

-- profiles
drop policy if exists "read own or staff reads all" on public.profiles;
drop policy if exists "read basic profile info if approved" on public.profiles;
-- Allow any approved authenticated user to see other approved profiles.
-- (Needed for the org chart and to display author names next to posts.)
create policy "read basic profile info if approved" on public.profiles
  for select using (
    id = auth.uid()
    or public.is_staff()
    or (public.is_approved() and account_status = 'approved')
  );

drop policy if exists "update own basic info" on public.profiles;
create policy "update own basic info" on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles where id = auth.uid())
    and account_status = (select account_status from public.profiles where id = auth.uid())
    and leader_id is not distinct from (select leader_id from public.profiles where id = auth.uid())
  );

drop policy if exists "admins manage profiles" on public.profiles;
create policy "admins manage profiles" on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- posts
drop policy if exists "read approved posts" on public.posts;
create policy "read approved posts" on public.posts
  for select using (status = 'approved' or author_id = auth.uid() or public.is_staff());

drop policy if exists "approved users create posts" on public.posts;
create policy "approved users create posts" on public.posts
  for insert with check (author_id = auth.uid() and public.is_approved());

drop policy if exists "author updates own pending" on public.posts;
create policy "author updates own pending" on public.posts
  for update using (author_id = auth.uid() and status = 'pending')
  with check (author_id = auth.uid());

drop policy if exists "staff moderates posts" on public.posts;
create policy "staff moderates posts" on public.posts
  for update using (public.is_staff()) with check (public.is_staff());

drop policy if exists "staff deletes posts" on public.posts;
create policy "staff deletes posts" on public.posts
  for delete using (public.is_staff() or author_id = auth.uid());

-- discussions
drop policy if exists "read approved discussions" on public.discussions;
create policy "read approved discussions" on public.discussions
  for select using (status = 'approved' or author_id = auth.uid() or public.is_staff());

drop policy if exists "approved users create discussions" on public.discussions;
create policy "approved users create discussions" on public.discussions
  for insert with check (author_id = auth.uid() and public.is_approved());

drop policy if exists "author updates own pending discussion" on public.discussions;
create policy "author updates own pending discussion" on public.discussions
  for update using (author_id = auth.uid() and status = 'pending')
  with check (author_id = auth.uid());

drop policy if exists "staff moderates discussions" on public.discussions;
create policy "staff moderates discussions" on public.discussions
  for update using (public.is_staff()) with check (public.is_staff());

drop policy if exists "staff deletes discussions" on public.discussions;
create policy "staff deletes discussions" on public.discussions
  for delete using (public.is_staff() or author_id = auth.uid());

-- comments (unified). Only approved parent content is commentable.
drop policy if exists "read comments on approved content" on public.comments;
create policy "read comments on approved content" on public.comments
  for select using (
    public.is_staff()
    or (entity_type = 'post' and exists (
          select 1 from public.posts p where p.id = entity_id and p.status = 'approved'))
    or (entity_type = 'discussion' and exists (
          select 1 from public.discussions d where d.id = entity_id and d.status = 'approved'))
  );

drop policy if exists "approved users comment" on public.comments;
create policy "approved users comment" on public.comments
  for insert with check (
    author_id = auth.uid()
    and public.is_approved()
    and (
      (entity_type = 'post' and exists (
          select 1 from public.posts p where p.id = entity_id and p.status = 'approved'))
      or (entity_type = 'discussion' and exists (
          select 1 from public.discussions d where d.id = entity_id and d.status = 'approved'))
    )
  );

drop policy if exists "author or staff deletes comment" on public.comments;
create policy "author or staff deletes comment" on public.comments
  for delete using (author_id = auth.uid() or public.is_staff());

-- reactions
drop policy if exists "read reactions on approved content" on public.reactions;
create policy "read reactions on approved content" on public.reactions
  for select using (
    public.is_staff()
    or (entity_type = 'post' and exists (
          select 1 from public.posts p where p.id = entity_id and p.status = 'approved'))
    or (entity_type = 'discussion' and exists (
          select 1 from public.discussions d where d.id = entity_id and d.status = 'approved'))
  );

drop policy if exists "approved users react" on public.reactions;
create policy "approved users react" on public.reactions
  for insert with check (user_id = auth.uid() and public.is_approved());

drop policy if exists "remove own reaction" on public.reactions;
create policy "remove own reaction" on public.reactions
  for delete using (user_id = auth.uid());

-- events
drop policy if exists "everyone reads events" on public.events;
create policy "everyone reads events" on public.events
  for select using (true);

drop policy if exists "admins manage events" on public.events;
create policy "admins manage events" on public.events
  for all using (public.is_admin()) with check (public.is_admin());

-- messages
drop policy if exists "read own messages" on public.messages;
create policy "read own messages" on public.messages
  for select using (sender_id = auth.uid() or recipient_id = auth.uid());

drop policy if exists "approved users send messages" on public.messages;
create policy "approved users send messages" on public.messages
  for insert with check (sender_id = auth.uid() and public.is_approved());

drop policy if exists "recipient marks read" on public.messages;
create policy "recipient marks read" on public.messages
  for update using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- Post media (images + videos) is stored on the local filesystem
-- via /api/upload → public/uploads/…, not Supabase Storage.
-- If a legacy bucket exists, we leave it alone; no policies here.

-- =========================================================
-- Storage bucket for profile avatars
-- =========================================================
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

drop policy if exists "avatars public read" on storage.objects;
create policy "avatars public read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars upload own folder" on storage.objects;
create policy "avatars upload own folder" on storage.objects
  for insert with check (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars update own folder" on storage.objects;
create policy "avatars update own folder" on storage.objects
  for update using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars delete own folder" on storage.objects;
create policy "avatars delete own folder" on storage.objects
  for delete using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

-- =========================================================
-- Auto-promote Super Admin — runs every schema re-execution
-- so you never lose access when re-applying the schema.
-- Edit the email if you switch owners.
-- =========================================================
do $$
declare
  admin_email text := 'siena.alfreddenly@gmail.com';
  uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(admin_email);
  if uid is not null then
    insert into public.profiles (id, full_name, email, role, account_status, is_leader)
      values (uid, 'Siena Alfreddenly', admin_email, 'super_admin', 'approved', true)
    on conflict (id) do update
      set role = 'super_admin', account_status = 'approved', is_leader = true;
  end if;
end $$;
