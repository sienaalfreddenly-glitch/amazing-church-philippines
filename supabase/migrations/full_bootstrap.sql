-- ==========================================================
-- Amazing Church Philippines: full bootstrap
-- Paste into Supabase SQL Editor and Run once. Idempotent.
-- schema.sql plus every migration in order.
-- ==========================================================

-- Drop functions whose return signature changes across migrations.
-- Their bodies are recreated by later CREATE OR REPLACE statements.
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);

-- ---------- schema.sql ----------
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
alter table public.profiles add column if not exists must_change_password boolean not null default false;
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
  entity_type text not null check (entity_type in ('post','discussion','comment')),
  entity_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 8),
  created_at timestamptz not null default now(),
  unique (entity_type, entity_id, user_id, emoji)
);
-- Broaden the check constraint if the table was created with the old two-value list
alter table public.reactions drop constraint if exists reactions_entity_type_check;
alter table public.reactions add constraint reactions_entity_type_check
  check (entity_type in ('post','discussion','comment'));
create index if not exists reactions_entity_idx on public.reactions (entity_type, entity_id);

-- Mentions on posts/discussions/comments (array of profile ids)
alter table public.posts       add column if not exists mentions uuid[] not null default '{}';
alter table public.discussions add column if not exists mentions uuid[] not null default '{}';
alter table public.comments    add column if not exists mentions uuid[] not null default '{}';

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

-- =========================================================
-- News & Updates (admin-authored posts, everyone can read)
-- =========================================================
create table if not exists public.news_posts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  media_urls text[] not null default '{}',    -- uploaded photos/videos
  video_url text,                              -- optional external video (YouTube / FB)
  author_id uuid references public.profiles(id) on delete set null,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists news_posts_published_idx on public.news_posts (published_at desc);

-- =========================================================
-- Hero slideshow images (behind the home page "Welcome home" hero)
-- =========================================================
create table if not exists public.hero_slides (
  id uuid primary key default gen_random_uuid(),
  image_url text not null,
  caption text,
  ord int not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists hero_slides_ord_idx on public.hero_slides (ord);

create table if not exists public.live_series (
  id uuid primary key default gen_random_uuid(),
  title text not null unique,
  description text,
  cover_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.live_videos (
  id uuid primary key default gen_random_uuid(),
  series_id uuid references public.live_series(id) on delete set null,
  title text not null,
  video_url text not null,
  occurred_on date not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
alter table public.live_videos add column if not exists series_id uuid references public.live_series(id) on delete set null;
create index if not exists live_videos_occurred_idx on public.live_videos (occurred_on desc);
create index if not exists live_videos_series_idx on public.live_videos (series_id);

-- =========================================================
-- Courses (discipleship tracks, e.g. SOL 1 → SOL 2 → SOL 3)
-- =========================================================
do $$ begin
  create type enrollment_status as enum ('enrolled', 'completed', 'dropped');
exception when duplicate_object then null; end $$;

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,          -- e.g. "SOL 1"
  name text not null,                 -- e.g. "School of Leaders 1"
  description text,
  prereq_id uuid references public.courses(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
-- Legacy: drop the old level column if it exists
alter table public.courses drop column if exists level;

create table if not exists public.course_lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  ord int not null default 1,               -- display order within the course
  title text not null,
  description text,
  meeting_at timestamptz,
  meeting_url text,
  meeting_location text,
  slides_url text,
  assignment_title text,
  assignment_body text,
  assignment_due_at timestamptz,
  todo_items text[] not null default '{}',  -- simple checklist for the student
  created_at timestamptz not null default now()
);
create index if not exists course_lessons_course_idx on public.course_lessons (course_id, ord);

create table if not exists public.lesson_completions (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  lesson_id uuid not null references public.course_lessons(id) on delete cascade,
  verified_by uuid references public.profiles(id),
  verified_at timestamptz not null default now(),
  notes text,
  unique (enrollment_id, lesson_id)
);
create index if not exists lesson_completions_enrollment_idx on public.lesson_completions (enrollment_id);

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  status enrollment_status not null default 'enrolled',
  enrolled_by uuid references public.profiles(id),
  enrolled_at timestamptz not null default now(),
  completed_at timestamptz,
  notes text,
  unique (user_id, course_id)
);
create index if not exists enrollments_user_idx on public.enrollments (user_id);
create index if not exists enrollments_course_idx on public.enrollments (course_id);

-- =========================================================
-- Notifications
-- =========================================================
do $$ begin
  create type notification_kind as enum ('enrolled','lesson_verified','reaction','comment','mention');
exception when duplicate_object then null; end $$;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,   -- recipient
  actor_id uuid references public.profiles(id) on delete set null,          -- who triggered
  kind notification_kind not null,
  entity_type text,           -- 'post' | 'discussion' | 'comment' | 'course' | 'lesson'
  entity_id uuid,
  metadata jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_idx on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx on public.notifications (user_id) where read_at is null;

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
alter table public.live_series enable row level security;

drop policy if exists "everyone reads live series" on public.live_series;
create policy "everyone reads live series" on public.live_series
  for select using (true);

drop policy if exists "staff manage live series" on public.live_series;
create policy "staff manage live series" on public.live_series
  for all using (public.is_staff()) with check (public.is_staff());

alter table public.courses enable row level security;
alter table public.course_lessons enable row level security;
alter table public.lesson_completions enable row level security;
alter table public.enrollments enable row level security;
alter table public.news_posts enable row level security;
alter table public.hero_slides enable row level security;

drop policy if exists "everyone reads news" on public.news_posts;
create policy "everyone reads news" on public.news_posts
  for select using (true);
drop policy if exists "admins manage news" on public.news_posts;
create policy "admins manage news" on public.news_posts
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "everyone reads hero slides" on public.hero_slides;
create policy "everyone reads hero slides" on public.hero_slides
  for select using (is_active or public.is_admin());
drop policy if exists "admins manage hero slides" on public.hero_slides;
create policy "admins manage hero slides" on public.hero_slides
  for all using (public.is_admin()) with check (public.is_admin());

alter table public.notifications enable row level security;
alter table public.messages enable row level security;

drop policy if exists "read own notifications" on public.notifications;
create policy "read own notifications" on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists "update own notifications" on public.notifications;
create policy "update own notifications" on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
-- No INSERT policy — notifications are only written by SECURITY DEFINER triggers below.

drop policy if exists "everyone reads lessons of active courses" on public.course_lessons;
create policy "everyone reads lessons of active courses" on public.course_lessons
  for select using (
    public.is_staff()
    or exists (select 1 from public.courses c where c.id = course_id and c.is_active)
  );

drop policy if exists "admins manage lessons" on public.course_lessons;
create policy "admins manage lessons" on public.course_lessons
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read own or all-if-staff completions" on public.lesson_completions;
create policy "read own or all-if-staff completions" on public.lesson_completions
  for select using (
    public.is_staff()
    or exists (
      select 1 from public.enrollments e
      where e.id = enrollment_id and e.user_id = auth.uid()
    )
  );

drop policy if exists "admins verify completions" on public.lesson_completions;
create policy "admins verify completions" on public.lesson_completions
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "everyone reads active courses" on public.courses;
create policy "everyone reads active courses" on public.courses
  for select using (is_active or public.is_staff());

drop policy if exists "admins manage courses" on public.courses;
create policy "admins manage courses" on public.courses
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists "own enrollments visible; staff sees all" on public.enrollments;
create policy "own enrollments visible; staff sees all" on public.enrollments
  for select using (user_id = auth.uid() or public.is_staff());

drop policy if exists "admins manage enrollments" on public.enrollments;
create policy "admins manage enrollments" on public.enrollments
  for all using (public.is_admin()) with check (public.is_admin());

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
drop policy if exists "staff manage events" on public.events;
create policy "staff manage events" on public.events
  for all using (public.is_staff()) with check (public.is_staff());

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

-- =========================================================
-- Storage bucket for post + news + hero media (images + short videos)
-- Uploads go through Supabase Storage because Vercel's serverless
-- filesystem is read-only. This still runs in local Docker (no Cloud
-- Storage quota used).
-- =========================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('post-media', 'post-media', true, 52428800,
          array['image/png','image/jpeg','image/gif','image/webp','video/mp4','video/webm','video/quicktime'])
  on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "post-media public read" on storage.objects;
create policy "post-media public read" on storage.objects
  for select using (bucket_id = 'post-media');

drop policy if exists "post-media upload own folder" on storage.objects;
create policy "post-media upload own folder" on storage.objects
  for insert with check (
    bucket_id = 'post-media' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "post-media delete own folder" on storage.objects;
create policy "post-media delete own folder" on storage.objects
  for delete using (
    bucket_id = 'post-media' and (
      auth.uid()::text = (storage.foldername(name))[1]
      or public.is_admin()
    )
  );

-- =========================================================
-- Notification triggers (SECURITY DEFINER so users can only insert
-- notifications indirectly through these functions).
-- =========================================================
create or replace function public.notify_reaction() returns trigger
language plpgsql security definer set search_path = public as $$
declare tgt uuid;
begin
  if new.entity_type = 'post' then
    select author_id into tgt from public.posts where id = new.entity_id;
  elsif new.entity_type = 'discussion' then
    select author_id into tgt from public.discussions where id = new.entity_id;
  elsif new.entity_type = 'comment' then
    select author_id into tgt from public.comments where id = new.entity_id;
  end if;
  if tgt is not null and tgt <> new.user_id then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (tgt, new.user_id, 'reaction', new.entity_type, new.entity_id,
            jsonb_build_object('emoji', new.emoji));
  end if;
  return new;
end $$;
drop trigger if exists reactions_notify on public.reactions;
create trigger reactions_notify after insert on public.reactions
  for each row execute function public.notify_reaction();

create or replace function public.notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare tgt uuid; m uuid;
begin
  if new.entity_type = 'post' then
    select author_id into tgt from public.posts where id = new.entity_id;
  elsif new.entity_type = 'discussion' then
    select author_id into tgt from public.discussions where id = new.entity_id;
  end if;
  if tgt is not null and tgt <> new.author_id then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
    values (tgt, new.author_id, 'comment', new.entity_type, new.entity_id);
  end if;
  if new.mentions is not null then
    foreach m in array new.mentions loop
      if m is not null and m <> new.author_id then
        insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
        values (m, new.author_id, 'mention', 'comment', new.id);
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists comments_notify on public.comments;
create trigger comments_notify after insert on public.comments
  for each row execute function public.notify_comment();

create or replace function public.notify_post_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
declare m uuid; ent text;
begin
  ent := case when tg_table_name = 'posts' then 'post' else 'discussion' end;
  if new.mentions is not null then
    foreach m in array new.mentions loop
      if m is not null and m <> new.author_id then
        insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
        values (m, new.author_id, 'mention', ent, new.id);
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists posts_notify_mentions on public.posts;
create trigger posts_notify_mentions after insert on public.posts
  for each row execute function public.notify_post_mentions();
drop trigger if exists discussions_notify_mentions on public.discussions;
create trigger discussions_notify_mentions after insert on public.discussions
  for each row execute function public.notify_post_mentions();

create or replace function public.notify_enrollment() returns trigger
language plpgsql security definer set search_path = public as $$
declare course_code text;
begin
  select code into course_code from public.courses where id = new.course_id;
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  values (new.user_id, new.enrolled_by, 'enrolled', 'course', new.course_id,
          jsonb_build_object('course_code', course_code));
  return new;
end $$;
drop trigger if exists enrollments_notify on public.enrollments;
create trigger enrollments_notify after insert on public.enrollments
  for each row execute function public.notify_enrollment();

create or replace function public.notify_lesson_verified() returns trigger
language plpgsql security definer set search_path = public as $$
declare tgt uuid; lesson_title text; course_code text;
begin
  select user_id into tgt from public.enrollments where id = new.enrollment_id;
  select cl.title, c.code into lesson_title, course_code
    from public.course_lessons cl join public.courses c on c.id = cl.course_id
    where cl.id = new.lesson_id;
  if tgt is not null then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (tgt, new.verified_by, 'lesson_verified', 'lesson', new.lesson_id,
            jsonb_build_object('lesson_title', lesson_title, 'course_code', course_code));
  end if;
  return new;
end $$;
drop trigger if exists lesson_completions_notify on public.lesson_completions;
create trigger lesson_completions_notify after insert on public.lesson_completions
  for each row execute function public.notify_lesson_verified();

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

-- ---------- 20260911_broadcast_and_mutes.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Three things: hide the website maintenance account from the congregation,
-- tell everyone when something is posted, and let anyone quietly stop hearing
-- from one particular person.

-- ---------------------------------------------------------------------------
-- 1. The maintenance account
--
-- siena.alfreddenly@gmail.com exists to build and fix the site, not to be a
-- member of the church. It should not appear in the leaders list, the org
-- chart, the signup leader dropdown, or a ministry roster. It still posts, and
-- those posts still notify people, because announcements sometimes come from it.
--
-- Hiding is presentational only. It does not touch the account's super admin
-- role, so nothing about administering the site changes.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_hidden boolean not null default false;

comment on column public.profiles.is_hidden is
  'Service account. Hidden from directories and the org chart; only a super admin sees it.';

update public.profiles
set is_hidden = true, is_leader = false, title = null
where email = 'siena.alfreddenly@gmail.com';

-- Every directory read now filters on this flag.
create or replace function public.list_leaders()
returns table (id uuid, full_name text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name
  from public.profiles p
  where p.is_leader = true
    and p.account_status = 'approved'
    and p.is_hidden = false
  order by p.full_name;
$$;
revoke all on function public.list_leaders() from public;
grant execute on function public.list_leaders() to anon, authenticated;

create or replace function public.org_chart()
returns table (
  id uuid, full_name text, title text, avatar_url text, leader_id uuid, is_leader boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.title, p.avatar_url, p.leader_id, p.is_leader
  from public.profiles p
  where p.account_status = 'approved'
    and p.is_hidden = false
    and p.role <> 'super_admin'
  order by p.is_leader desc, p.full_name;
$$;
revoke all on function public.org_chart() from public;
grant execute on function public.org_chart() to authenticated;

create or replace function public.ministry_teams()
returns table (
  ministry_id uuid, profile_id uuid, full_name text, avatar_url text, role_in_team text
)
language sql
security definer
set search_path = public
stable
as $$
  select mi.ministry_id, p.id, p.full_name, p.avatar_url, mi.role_in_team
  from public.ministry_interests mi
  join public.profiles p on p.id = mi.profile_id
  where mi.status = 'member'
    and p.account_status = 'approved'
    and p.is_hidden = false
  order by p.full_name;
$$;
revoke all on function public.ministry_teams() from public;
grant execute on function public.ministry_teams() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Muting a person
--
-- Deliberately invisible to everyone but the person who set it. Not to the
-- muted person, and not to leaders or admins either. A mute that someone else
-- can look up is a social problem waiting to happen, and nobody would trust it.
-- ---------------------------------------------------------------------------

create table if not exists public.notification_mutes (
  muter_id   uuid not null references public.profiles(id) on delete cascade,
  muted_id   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint no_self_mute check (muter_id <> muted_id)
);

alter table public.notification_mutes enable row level security;

-- The only policy on this table, on purpose. There is no staff exception.
drop policy if exists "a mute belongs to the person who set it" on public.notification_mutes;
create policy "a mute belongs to the person who set it"
  on public.notification_mutes for all
  using (muter_id = auth.uid())
  with check (muter_id = auth.uid());

grant select, insert, delete on public.notification_mutes to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Telling everyone when something is posted
-- ---------------------------------------------------------------------------

alter type public.notification_kind add value if not exists 'new_post';
alter type public.notification_kind add value if not exists 'new_discussion';
alter type public.notification_kind add value if not exists 'new_news';
alter type public.notification_kind add value if not exists 'new_event';

-- One routine for all four kinds of content. Everyone approved hears about it
-- except the author, anyone who muted the author, and the hidden service
-- account, which has nobody reading its bell.
create or replace function public.broadcast_to_members(
  p_author uuid,
  p_kind   public.notification_kind,
  p_entity_type text,
  p_entity_id   uuid,
  p_metadata    jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, p_author, p_kind, p_entity_type, p_entity_id, p_metadata
  from public.profiles p
  where p.account_status = 'approved'
    and p.is_hidden = false
    and p.id <> p_author
    and not exists (
      select 1 from public.notification_mutes m
      where m.muter_id = p.id and m.muted_id = p_author
    );
$$;

create or replace function public.notify_new_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  -- Only announce what is actually visible. A post held for moderation should
  -- not ring every phone in the church.
  if new.status is distinct from 'approved' then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

create or replace function public.notify_new_discussion()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if new.status is distinct from 'approved' then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_discussion', 'discussion', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

create or replace function public.notify_new_news()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_news', 'news', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

create or replace function public.notify_new_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  select full_name into who from public.profiles where id = new.created_by;
  perform broadcast_to_members(new.created_by, 'new_event', 'event', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

drop trigger if exists on_new_post       on public.posts;
drop trigger if exists on_new_discussion on public.discussions;
drop trigger if exists on_new_news       on public.news_posts;
drop trigger if exists on_new_event      on public.events;

create trigger on_new_post       after insert on public.posts       for each row execute function public.notify_new_post();
create trigger on_new_discussion after insert on public.discussions for each row execute function public.notify_new_discussion();
create trigger on_new_news       after insert on public.news_posts  for each row execute function public.notify_new_news();
create trigger on_new_event      after insert on public.events      for each row execute function public.notify_new_event();

-- A post that clears moderation later should announce itself then, not never.
create or replace function public.notify_post_approved()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select full_name into who from public.profiles where id = new.author_id;
    perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
      jsonb_build_object('full_name', who, 'title', new.title));
  end if;
  return new;
end $$;

drop trigger if exists on_post_approved on public.posts;
create trigger on_post_approved after update of status on public.posts
  for each row execute function public.notify_post_approved();

-- ---------- 20260911_contact_privacy_consent_titles.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Three things: make phone numbers genuinely private, record consent to the
-- information agreement, and give the church real titles for the org chart.

-- ---------------------------------------------------------------------------
-- 1. Phone numbers
--
-- Until now the show_contact flag only changed what the interface drew. The
-- read policy on profiles lets any approved member select any other approved
-- member's whole row, so every phone number was readable by every member
-- regardless of the toggle. Privacy that only exists in the UI is not privacy.
--
-- Postgres has no conditional column privilege, so the column is taken away
-- from ordinary members entirely and handed back through a function that
-- checks who is asking.
-- ---------------------------------------------------------------------------

-- A column-level revoke cannot subtract from a table-level grant: Postgres
-- treats SELECT on the table as covering every column, including ones added
-- later. So the table grant is withdrawn first and the readable columns are
-- granted back by name. A new column is therefore invisible to members until
-- it is deliberately added to this list, which is the safer default.
revoke select on public.profiles from authenticated, anon;

grant select (
  id, full_name, email, role, account_status, avatar_url,
  leader_id, created_at, is_leader, must_change_password,
  facebook_url, instagram_url, title,
  terms_accepted_at, terms_accepted_version
) on public.profiles to authenticated;

grant select (id, full_name, is_leader, title, account_status)
  on public.profiles to anon;

create or replace function public.profile_contact(target uuid)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  number     text;
  owner_lead uuid;
begin
  select p.contact_number, p.leader_id into number, owner_lead
  from public.profiles p where p.id = target;

  if number is null then
    return null;
  end if;

  -- Yourself: always.
  if target = auth.uid() then
    return number;
  end if;

  -- Staff: pastoral care and administration need to reach people.
  if is_staff() then
    return number;
  end if;

  -- The member's own leader: that is the point of having one.
  if owner_lead is not null and owner_lead = auth.uid() then
    return number;
  end if;

  -- Everyone else, including other members who were shown it before.
  return null;
end;
$$;

revoke all on function public.profile_contact(uuid) from public;
grant execute on function public.profile_contact(uuid) to authenticated;

comment on function public.profile_contact(uuid) is
  'Returns a member phone number only to that member, their leader, or staff.';

-- show_contact no longer gates anything, because the rule is now fixed rather
-- than chosen. Dropped so nobody mistakes it for a live privacy control.
alter table public.profiles drop column if exists show_contact;

-- ---------------------------------------------------------------------------
-- 2. Consent to the information agreement
--
-- Recorded as a timestamp and a version rather than a boolean, so that when the
-- agreement is reworded it is possible to tell who accepted which text and who
-- still needs to re-accept.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists terms_accepted_at      timestamptz,
  add column if not exists terms_accepted_version text;

comment on column public.profiles.terms_accepted_at is
  'When this member accepted the information agreement. Null means never.';
comment on column public.profiles.terms_accepted_version is
  'Which version of the agreement text they accepted.';

-- ---------------------------------------------------------------------------
-- 3. Titles and the org chart
--
-- is_leader answers "does anyone report to this person". It cannot say what
-- someone is called, and the pastor is not a "Leader". Title is free text
-- because a church invents roles faster than any enum can follow.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists title text;

comment on column public.profiles.title is
  'What this person is called in the church, e.g. Head Pastor. Shown on the org chart.';

update public.profiles
set title = 'Head Pastor', leader_id = null
where full_name ilike 'Joey%Miralo%';

-- Anyone else already marked as a leader gets a sensible default they can edit.
update public.profiles
set title = 'Leader'
where is_leader = true and title is null;

-- ---------------------------------------------------------------------------
-- 4. The org chart read
--
-- Every approved member can already see names, so the chart exposes nothing
-- new. It goes through a function so the shape is decided once, in one place,
-- rather than reassembled by each caller.
-- ---------------------------------------------------------------------------

create or replace function public.org_chart()
returns table (
  id uuid,
  full_name text,
  title text,
  avatar_url text,
  leader_id uuid,
  is_leader boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.title, p.avatar_url, p.leader_id, p.is_leader
  from public.profiles p
  where p.account_status = 'approved'
  order by p.is_leader desc, p.full_name;
$$;

revoke all on function public.org_chart() from public;
grant execute on function public.org_chart() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Bulk contact lookup
--
-- The admin members list and a leader's group both show many people at once.
-- Calling profile_contact once per row would be a query per member, so this
-- returns every number the caller is entitled to in a single call. The
-- entitlement rule is the same one profile_contact applies.
-- ---------------------------------------------------------------------------

create or replace function public.visible_contacts()
returns table (id uuid, contact_number text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.contact_number
  from public.profiles p
  where p.contact_number is not null
    and (
      p.id = auth.uid()
      or is_staff()
      or p.leader_id = auth.uid()
    );
$$;

revoke all on function public.visible_contacts() from public;
grant execute on function public.visible_contacts() to authenticated;

comment on function public.visible_contacts() is
  'Phone numbers the caller may see: their own, their group members, or all if staff.';

-- ---------------------------------------------------------------------------
-- 6. Record the agreement at signup
--
-- The signup form sends the version it displayed. Storing it here, rather than
-- letting the browser write it afterwards, means acceptance is recorded in the
-- same transaction as the account and cannot be skipped by calling the API
-- directly.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_leader uuid;
  leader_row    record;
  agreed        text;
begin
  begin
    chosen_leader := nullif(new.raw_user_meta_data->>'leader_id', '')::uuid;
  exception when others then
    chosen_leader := null;
  end;

  if chosen_leader is not null then
    if not exists (
      select 1 from public.profiles
      where id = chosen_leader and is_leader = true and account_status = 'approved'
    ) then
      chosen_leader := null;
    end if;
  end if;

  agreed := nullif(new.raw_user_meta_data->>'terms_accepted_version', '');

  insert into public.profiles (
    id, full_name, email, leader_id, terms_accepted_version, terms_accepted_at
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    chosen_leader,
    agreed,
    case when agreed is not null then now() end
  )
  on conflict (id) do nothing;

  if chosen_leader is null then
    for leader_row in
      select id from public.profiles
      where is_leader = true and account_status = 'approved'
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (
        leader_row.id,
        new.id,
        'unassigned_member',
        'profile',
        new.id,
        jsonb_build_object(
          'full_name', coalesce(new.raw_user_meta_data->>'full_name', new.email),
          'email', new.email
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ---------- 20260911_daily_assignments.sql ----------
-- Daily Bible Verse: one unique verse and reminder per person per day.
--
-- HOW UNIQUENESS IS GUARANTEED
--
-- The verse and its reminder are stored together as one pool row rather than
-- being drawn from two independent pools. Pairing them means a single claim is
-- atomic: one row, one unique index, no window in which a user could get a
-- verse but lose the race for a reminder. It satisfies both requirements at
-- once, because claiming the pair claims the verse and the reminder together.
--
-- Two users cannot share content on the same day. That is enforced by a unique
-- index on (assigned_on, content_id), not by application logic, so simultaneous
-- requests, refreshes, and retries cannot defeat it. The claim loop inserts
-- with ON CONFLICT DO NOTHING and tries the next candidate if it lost the race.
--
-- REUSE POLICY, stated explicitly because the pool is finite
--
-- A given piece of content is never shown to two people on the same day. Across
-- different days it may be reused, and a person may see a verse again only once
-- they have seen everything else in the pool. Selection prefers content the
-- person has never had, then whatever has gone longest without being used
-- anywhere, so the same users do not always receive the first rows.
--
-- If every row is already taken for today the function returns nothing and the
-- page says so plainly, rather than handing out a duplicate.

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------------
-- The pool
-- ---------------------------------------------------------------------------

create table if not exists public.daily_content (
  id            uuid primary key default gen_random_uuid(),
  verse_ref     text not null,
  verse_text    text not null,
  reminder      text not null,
  theme         text not null,
  status        text not null default 'active' check (status in ('active', 'retired')),
  created_at    timestamptz not null default now(),

  -- Normalised once, by the database, so every comparison uses the same rules
  -- no matter which code path wrote the row: lower case, punctuation removed,
  -- whitespace collapsed.
  reminder_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,
  verse_ref_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(verse_ref), '[^a-z0-9: ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  -- Reject the obvious mistakes at write time rather than at read time.
  constraint reminder_length check (
    array_length(regexp_split_to_array(trim(reminder), '\s+'), 1) between 50 and 90
  ),
  constraint no_em_dash check (reminder !~ '[—–]' and verse_text !~ '[—–]'),
  constraint no_emoji check (reminder ~ '^[\x00-\x7F''’"“”]*$'),
  -- A reference must look like a reference: book, chapter, verse.
  constraint reference_shape check (verse_ref ~ '^[1-3]? ?[A-Z][A-Za-z ]+ [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$')
);

-- Exact duplicates are impossible.
create unique index if not exists daily_content_verse_ref_uniq  on public.daily_content (verse_ref_norm);
create unique index if not exists daily_content_reminder_uniq   on public.daily_content (reminder_norm);
-- Trigram index backing the similarity check below.
create index if not exists daily_content_reminder_trgm on public.daily_content using gin (reminder_norm gin_trgm_ops);

-- Near duplicates are impossible too. A reminder that reads like a light edit
-- of an existing one is refused on insert rather than being caught later.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  clash record;
begin
  select id, reminder, similarity(reminder_norm, new.reminder_norm) as score
    into clash
  from public.daily_content
  where id <> new.id
    and similarity(reminder_norm, new.reminder_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception
      'reminder is too similar (%.2f) to existing content %', clash.score, clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists daily_content_similarity on public.daily_content;
create trigger daily_content_similarity
  before insert or update of reminder on public.daily_content
  for each row execute function public.reject_similar_reminder();

-- ---------------------------------------------------------------------------
-- The assignments
-- ---------------------------------------------------------------------------

create table if not exists public.daily_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  content_id  uuid not null references public.daily_content(id) on delete restrict,
  assigned_on date not null,
  theme       text not null,
  status      text not null default 'active' check (status in ('active', 'superseded')),
  created_at  timestamptz not null default now(),

  -- One assignment per person per day, so a refresh returns what they already
  -- have instead of drawing again.
  constraint one_per_user_per_day unique (user_id, assigned_on),
  -- The guarantee that matters: nobody shares content with anybody else today.
  constraint one_holder_per_day   unique (assigned_on, content_id)
);

create index if not exists daily_assignments_user_idx    on public.daily_assignments (user_id, assigned_on desc);
create index if not exists daily_assignments_content_idx on public.daily_assignments (content_id, assigned_on desc);

alter table public.daily_content     enable row level security;
alter table public.daily_assignments enable row level security;

-- The pool itself is not readable directly; everything goes through the
-- function, so nobody can browse tomorrow's content or somebody else's.
drop policy if exists "assignments are private" on public.daily_assignments;
create policy "assignments are private"
  on public.daily_assignments for select
  using (user_id = auth.uid());

grant select on public.daily_assignments to authenticated;

-- ---------------------------------------------------------------------------
-- Claiming today's content
--
-- Race safety comes from the unique index, not from checking first and writing
-- second. Each attempt inserts with ON CONFLICT DO NOTHING; if another request
-- took that row in the meantime the insert simply affects no rows and the loop
-- tries the next candidate. No locks are held across the selection, so
-- simultaneous requests do not queue behind each other.
-- ---------------------------------------------------------------------------

create or replace function public.claim_daily_content(p_user uuid, p_day date)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate uuid;
  attempts  int := 0;
  made      uuid;
begin
  -- Already assigned today: hand back the same thing, every time.
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 25;

      select c.id into candidate
      from public.daily_content c
      where c.status = 'active'
        -- Not already given to somebody else today.
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.content_id = c.id
        )
      order by
        -- Content this person has never seen comes first.
        (exists (select 1 from public.daily_assignments a
                 where a.user_id = p_user and a.content_id = c.id)),
        -- Then whatever has gone longest unused by anyone, so the same rows are
        -- not always handed to whoever asks first.
        coalesce((select max(a.assigned_on) from public.daily_assignments a
                  where a.content_id = c.id), date '1970-01-01'),
        -- Stable shuffle within a day, so the order is not simply insertion
        -- order and is the same for retries within one request.
        md5(c.id::text || p_day::text)
      limit 1;

      -- Pool exhausted for today.
      exit when candidate is null;

      insert into public.daily_assignments (user_id, content_id, assigned_on, theme)
      select p_user, candidate, p_day, c.theme
      from public.daily_content c where c.id = candidate
      on conflict do nothing
      returning id into made;

      exit when made is not null;
      -- Lost the race for that row. Try again with the next candidate.
    end loop;
  end if;

  if made is null then
    return;  -- Caller shows a clear message rather than duplicate content.
  end if;

  return query
  select a.id, c.verse_ref, c.verse_text, c.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_content c on c.id = a.content_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;

-- What the app actually calls: always the signed-in user, always today in
-- Manila, so a caller cannot ask for somebody else's assignment.
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language sql
security definer
set search_path = public
as $$
  select * from public.claim_daily_content(
    auth.uid(),
    (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;
-- Fix 1: validate the book, not merely the shape.
--
-- The old check only confirmed the reference looked like "Word 3:16", so
-- Hezekiah 3:16 passed as well formed. A fabricated book is exactly the failure
-- the brief asks to prevent, so the 66 real books are now the test.
create or replace function public.is_valid_bible_reference(ref text)
returns boolean
language sql
immutable
as $$
  select ref ~ ('^(' || array_to_string(array[
    'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
    '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles','Ezra',
    'Nehemiah','Esther','Job','Psalms','Psalm','Proverbs','Ecclesiastes','Song of Solomon',
    'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
    'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
    'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
    'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
    '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
    '1 John','2 John','3 John','Jude','Revelation'
  ], '|') || ') [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$');
$$;

alter table public.daily_content drop constraint if exists reference_shape;
alter table public.daily_content
  add constraint reference_is_real check (public.is_valid_bible_reference(verse_ref));

-- Fix 2: the similarity guard was comparing against nothing.
--
-- reminder_norm is a STORED generated column, and generated columns are
-- computed after before-insert triggers run. new.reminder_norm was therefore
-- always null inside the trigger, similarity() returned null, and no candidate
-- ever exceeded the threshold. Normalise from new.reminder directly instead.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  candidate_norm text;
  clash record;
begin
  candidate_norm := trim(regexp_replace(
    regexp_replace(lower(new.reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));

  select id, similarity(reminder_norm, candidate_norm) as score
    into clash
  from public.daily_content
  where id <> new.id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to existing content %', round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

-- ---------- 20260911_daily_content_seed.sql ----------
insert into public.daily_content (verse_ref, verse_text, reminder, theme) values
('Zephaniah 3:17',
 'The Lord your God is with you, the Mighty Warrior who saves. He will take great delight in you; in his love he will no longer rebuke you, but will rejoice over you with singing.',
 'You may have spent today feeling like nobody really noticed you. God did. He is not standing at a distance waiting for you to become impressive first. He is close, and he is glad about you, right now, in the middle of the ordinary day you just had. You do not need to earn that. Let it settle on you before you sleep tonight.',
 'God''s love'),

('Isaiah 41:10',
 'So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.',
 'Fear has a way of making everything feel bigger than it is. If something is sitting heavy on you today, you are not facing it by yourself. God does not ask you to be brave on your own strength. He offers his. You might still feel shaky. That is fine. Being held is not the same as feeling strong, and you are being held.',
 'Courage when facing fear'),

('Lamentations 3:22-23',
 'Because of the Lord''s great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness.',
 'If yesterday went badly, you are not starting today with a deficit. God''s kindness does not run low because you used some of it already. Whatever you got wrong, whatever you said that you wish you could take back, this morning is genuinely new. You are allowed to begin again. Not because you fixed it, but because he keeps giving mornings away.',
 'Forgiveness and grace'),

('Matthew 11:28',
 'Come to me, all you who are weary and burdened, and I will give you rest.',
 'Being tired is not a character flaw. If you have been running on very little for weeks, God is not asking you to push harder. He is asking you to come and put some of it down. Rest is not laziness and it is not giving up. Sometimes the most faithful thing you can do is stop, eat something, and sleep properly tonight.',
 'Rest when feeling tired'),

('Psalm 27:14',
 'Wait for the Lord; be strong and take heart and wait for the Lord.',
 'Waiting is its own kind of work, and nobody claps for it. If you are still waiting on an answer, a job, a diagnosis, or a person to come round, that stretch of time is not wasted. God has not forgotten the thing you are waiting for. You are allowed to find it hard. Keep going a little longer. You are not as far from it as it feels.',
 'Hope while waiting'),

('Philippians 4:6-7',
 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.',
 'When your head will not stop going round the same worry, you do not have to sort it out before you pray. Say it plainly, as messy as it is. Peace may not arrive as an answer. Often it arrives as the ability to put something down for the night and pick it up tomorrow. That is still God looking after you.',
 'Peace during stressful moments'),

('Proverbs 3:5-6',
 'Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.',
 'You do not need the whole map before you take the next step. Most of us only ever get enough light for the bit of road in front of us. If a decision is weighing on you, you are not failing because you cannot see how it ends. Ask God, take the next honest step, and trust him with the part you cannot work out yet.',
 'Trusting God''s direction'),

('Joshua 1:9',
 'Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.',
 'Whatever you are walking into this week, you are not walking in alone. Courage is not the absence of nerves. It is doing the thing while your hands shake. God is already in the room you are dreading, the conversation you keep putting off, the place you have to go back to. He got there before you did and he is not leaving.',
 'Strength during difficult times');
insert into public.daily_content (verse_ref, verse_text, reminder, theme) values
('Psalm 34:18',
 'The Lord is close to the brokenhearted and saves those who are crushed in spirit.',
 'Grief does not run to a schedule, and there is no point at which you are supposed to be over it. If you are carrying a loss right now, God is not waiting on the other side of it for you to recover. He is near you in it. You can bring him the anger and the flatness as well as the tidy prayers. He can take all of it.',
 'Healing and comfort'),

('Galatians 6:9',
 'Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.',
 'You have been doing the right thing for a long time and it has not obviously paid off. That is exhausting, and it makes you wonder whether anyone noticed. God noticed. Faithful work often looks like nothing for a long while and then turns out to have mattered enormously. Do not judge the harvest by what you can see in November.',
 'Perseverance after disappointment'),

('James 1:5',
 'If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.',
 'If you are stuck on a decision, you are allowed to admit you do not know what to do. God does not sigh at people who ask. There is no quota of questions after which he loses patience. Ask plainly, talk it through with someone wiser than you, and give it a bit of time. Clarity usually arrives slowly rather than all at once.',
 'Wisdom and guidance'),

('1 Thessalonians 5:16-18',
 'Rejoice always, pray continually, give thanks in all circumstances; for this is God''s will for you in Christ Jesus.',
 'Gratitude is not pretending the hard thing is fine. It is noticing that alongside the hard thing there was a decent cup of coffee, someone who texted back, and a bed to sleep in tonight. Naming those does not cancel the struggle. It just stops the struggle being the only thing you can see. Try naming three before you sleep.',
 'Gratitude'),

('Romans 8:28',
 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.',
 'This does not mean everything that happens to you is good. Some of it is genuinely awful and God is not the author of it. What it means is that nothing is so wasted that he cannot bring something out of it. The part of your life you would rather skip is not outside his reach. He is working, even where you cannot see it.',
 'Purpose and faith'),

('Psalm 46:10',
 'Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.',
 'You do not have to hold the whole world together today. Most of what you are anxious about is not actually yours to carry, and some of it was never going to happen anyway. Put the phone down for ten minutes. Sit somewhere quiet. God is still God whether or not you are keeping every plate in the air, and that is good news.',
 'Peace during stressful moments'),

('Isaiah 40:31',
 'But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.',
 'Strength does not usually arrive as a sudden surge. It arrives as enough for today, and then enough for tomorrow. If you are running on empty, stop measuring yourself against the version of you who had more energy. God gives what is needed for the day you are actually in. Walking counts. You do not have to soar this week.',
 'Strength during difficult times'),

('Ephesians 4:32',
 'Be kind and compassionate to one another, forgiving each other, just as in Christ God forgave you.',
 'Forgiving someone does not mean saying that what they did was acceptable. It means deciding not to carry the debt around any longer, because it is heavy and it is costing you more than it costs them. That can take a long time and you may have to decide it more than once. Start where you actually are, not where you think you should be.',
 'Forgiveness and grace');
insert into public.daily_content (verse_ref, verse_text, reminder, theme) values
('1 Peter 5:7',
 'Cast all your anxiety on him because he cares for you.',
 'There is something you have not told anyone about, and you have been carrying it quietly for weeks. God already knows and he is not shocked. Saying it out loud to him is not informing him of anything. It is putting down something that was never meant to be carried alone. Tell him tonight, in ordinary words, and then get some sleep.',
 'Peace during stressful moments'),

('Colossians 3:23',
 'Whatever you do, work at it with all your heart, as working for the Lord, not for human masters.',
 'Your job may feel small and largely unnoticed. The work you did today still mattered, even if no one said so and nothing about it was interesting. God sees the care you put into things nobody checks. Doing a dull task honestly is not a lesser kind of faith. It is most of what faithfulness actually looks like across a normal working week.',
 'Purpose and faith'),

('Psalm 73:26',
 'My flesh and my heart may fail, but God is the strength of my heart and my portion forever.',
 'Bodies wear out and feelings run dry, and neither of those is a sign that your faith has failed. If you are unwell, or flat, or simply cannot summon the energy to care today, God has not withdrawn. He is not only available to the healthy and the upbeat. He is the steady thing underneath, especially on the days you have nothing to bring.',
 'Healing and comfort'),

('Romans 12:12',
 'Be joyful in hope, patient in affliction, faithful in prayer.',
 'Patience is not sitting still and feeling calm about it. Most of the time it is choosing not to force something open before it is ready, which is far harder. If you are tempted to push a situation or a person today, wait a little longer. Things that are rushed tend to need redoing. Give it the time it actually needs.',
 'Patience'),

('John 14:27',
 'Peace I leave with you; my peace I give you. I do not give to you as the world gives. Do not let your hearts be troubled and do not be afraid.',
 'The peace you are offered is not the kind that depends on everything going well. It can sit alongside a difficult diagnosis, a strained relationship, or money that does not stretch. You are not failing at faith because the circumstances still worry you. Peace here means you are not alone in them, and that is a different thing entirely.',
 'Peace during stressful moments'),

('Deuteronomy 31:8',
 'The Lord himself goes before you and will be with you; he will never leave you nor forsake you. Do not be afraid; do not be discouraged.',
 'If you are starting something new, or going back somewhere that hurt you, God is not sending you ahead by yourself. He goes first. Whatever is waiting there, he has already seen it. You are allowed to be nervous about it and still go. Being discouraged is not a sin. It is just tiredness, and it usually lifts once you begin.',
 'Courage when facing fear'),

('Psalm 121:1-2',
 'I lift up my eyes to the mountains, where does my help come from? My help comes from the Lord, the Maker of heaven and earth.',
 'When you cannot see a way through, it is worth remembering who you are actually asking. Not a distant force, but the one who made everything you can see out of the window. Your situation is not too complicated for him, and it is not too small to bother him with. Ask for help today, out loud, in your own words.',
 'Trusting God''s direction'),

('2 Corinthians 12:9',
 'But he said to me, My grace is sufficient for you, for my power is made perfect in weakness.',
 'You have probably been trying to hold it together in front of people who would understand if you did not. The weak spot you keep hiding is not disqualifying you from anything. God works through people who are honest about what they cannot do, far more often than through people who appear to have it handled. Let somebody see the real version this week.',
 'God''s love');

-- ---------- 20260911_ministries.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Ministries members can join, and a record of who has put their hand up.

create table if not exists public.ministries (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  -- One line for the listing, the fuller description underneath it.
  summary     text not null,
  calling     text not null,
  scripture     text not null,
  scripture_ref text not null,
  -- Free-form list so a ministry can describe itself without a schema change.
  duties      text[] not null default '{}',
  -- Who hears about new interest. Null means every leader is told instead, so
  -- an unassigned ministry does not silently swallow volunteers.
  leader_id   uuid references public.profiles(id) on delete set null,
  sort        int  not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.ministry_interests (
  id           uuid primary key default gen_random_uuid(),
  ministry_id  uuid not null references public.ministries(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  note         text,
  created_at   timestamptz not null default now(),
  -- Putting your hand up twice is the same as once.
  unique (ministry_id, profile_id)
);

create index if not exists ministry_interests_ministry_idx
  on public.ministry_interests (ministry_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------

alter table public.ministries        enable row level security;
alter table public.ministry_interests enable row level security;

drop policy if exists "anyone approved can read ministries" on public.ministries;
create policy "anyone approved can read ministries"
  on public.ministries for select
  using (is_approved() or is_staff());

drop policy if exists "admins manage ministries" on public.ministries;
create policy "admins manage ministries"
  on public.ministries for all
  using (is_admin()) with check (is_admin());

-- A member may put their own hand up and take it down again, and may see their
-- own entries. They must not be able to see who else volunteered: that list is
-- for the people who will act on it.
drop policy if exists "members record their own interest" on public.ministry_interests;
create policy "members record their own interest"
  on public.ministry_interests for insert
  with check (profile_id = auth.uid() and is_approved());

drop policy if exists "members withdraw their own interest" on public.ministry_interests;
create policy "members withdraw their own interest"
  on public.ministry_interests for delete
  using (profile_id = auth.uid());

drop policy if exists "read own interest, leaders read theirs" on public.ministry_interests;
create policy "read own interest, leaders read theirs"
  on public.ministry_interests for select
  using (
    profile_id = auth.uid()
    or is_staff()
    or exists (
      select 1 from public.ministries m
      where m.id = ministry_id and m.leader_id = auth.uid()
    )
  );

grant select, insert, delete on public.ministry_interests to authenticated;
grant select on public.ministries to authenticated;

-- ---------------------------------------------------------------------------
-- Telling the leaders
-- ---------------------------------------------------------------------------

alter type public.notification_kind add value if not exists 'ministry_interest';

create or replace function public.notify_ministry_interest()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m           record;
  volunteer   text;
  recipient   record;
begin
  select name, leader_id into m from public.ministries where id = new.ministry_id;
  select full_name into volunteer from public.profiles where id = new.profile_id;

  if m.leader_id is not null then
    -- The ministry has someone responsible; only they need to hear about it.
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (m.leader_id, new.profile_id, 'ministry_interest', 'ministry', new.ministry_id,
            jsonb_build_object('full_name', volunteer, 'ministry', m.name));
  else
    -- Nobody owns this ministry yet, so tell every leader rather than let the
    -- volunteer go unanswered.
    for recipient in
      select id from public.profiles where is_leader = true and account_status = 'approved'
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (recipient.id, new.profile_id, 'ministry_interest', 'ministry', new.ministry_id,
              jsonb_build_object('full_name', volunteer, 'ministry', m.name));
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists on_ministry_interest on public.ministry_interests;
create trigger on_ministry_interest
  after insert on public.ministry_interests
  for each row execute function public.notify_ministry_interest();

-- ---------------------------------------------------------------------------
-- The three ministries. Wording is editable from the database; these are the
-- starting descriptions.
-- ---------------------------------------------------------------------------

insert into public.ministries (slug, name, summary, calling, scripture, scripture_ref, duties, sort)
values
 ('ushering', 'Ushering Team',
  'The first face anyone sees on a Sunday.',
  'Ushering is hospitality as ministry. Most people decide whether they belong here long before the preaching starts, and that decision is usually made at the door. This team carries the welcome, and it is quiet work that rarely gets named from the front.',
  'Better is one day as a doorkeeper in the house of my God.',
  'Psalm 84:10',
  array[
    'Arrive before the congregation and pray over the room',
    'Greet people at the door, especially anyone who came alone',
    'Seat latecomers without making them feel late',
    'Handle the offering and the count with two people present',
    'Notice who is missing and tell a leader'
  ], 1),

 ('worship', 'Worship Team',
  'Leading the congregation in sung worship.',
  'The worship team exists to help the room sing, not to be listened to. That means the songs are chosen for the congregation rather than for the musicians, and it means rehearsal is a spiritual discipline as much as a musical one.',
  'Let the word of Christ dwell in you richly, singing with thankfulness in your hearts.',
  'Colossians 3:16',
  array[
    'Rehearse midweek, not just before the service',
    'Learn the songs well enough to look up from the music',
    'Keep keys singable for an ordinary voice',
    'Serve the congregation, not the performance',
    'Stay accountable to a leader in how you live, not only how you play'
  ], 2),

 ('tech-media', 'Tech and Media Team',
  'Sound, livestream, slides, and everything the room never notices.',
  'When this team does its work well nobody mentions it, and when it slips everybody does. Scripture names craftsmen as people God filled with skill for the work of the tabernacle. Technical ability is a gift given for the gathering, not a job that happens to need doing.',
  'I have filled him with the Spirit of God, with skill and with knowledge in every craft.',
  'Exodus 31:3',
  array[
    'Run sound, slides, and the livestream on a rota',
    'Arrive early for soundcheck and stay for pack-down',
    'Capture photos and clips for the feed and the page',
    'Keep the equipment maintained and the cables tidy',
    'Train the next person rather than becoming the only one who knows'
  ], 3)
on conflict (slug) do nothing;

-- ---------- 20260911_ministries_public_read.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Ministries are recruitment copy, not member data. The page sits in the public
-- menu, so a visitor deciding whether this church is for them should be able to
-- read what the teams do. Only active ones, and only the description; who is
-- interested and who serves stay behind their own rules.

drop policy if exists "anyone approved can read ministries" on public.ministries;

create policy "anyone can read active ministries"
  on public.ministries for select
  using (is_active = true or is_staff());

grant select on public.ministries to anon;

-- ---------- 20260911_ministry_copy_plain.sql ----------
-- Plainer wording. The earlier text read like a job description; this is closer
-- to how someone would actually explain it to you after a service.

update ministries set
  summary = 'The first face anyone sees on a Sunday.',
  calling = 'Most people work out whether they belong here before the preaching even starts, and usually that happens at the door. If you are the sort who notices the person standing on their own, this is your gift, and it matters more than it looks.',
  scripture = 'Better one day as a doorkeeper in the house of my God.'
where slug = 'ushering';

update ministries set
  summary = 'Helping the whole room sing.',
  calling = 'This team is not a band and the service is not a concert. The job is to help everyone else sing, which means picking songs ordinary voices can reach and knowing them well enough to look up from the music. You do not need to be the best musician in the room.',
  scripture = 'Let the word of Christ live in you, singing with thankful hearts.'
where slug = 'worship';

update ministries set
  summary = 'Sound, slides, livestream, and everything nobody notices.',
  calling = 'When this team gets it right nobody says a word, and when the microphone cuts out everybody does. Scripture talks about craftsmen God filled with skill to build the tabernacle. Being good with equipment is a gift too, not just a job that needs doing.',
  scripture = 'I have filled him with skill and knowledge in every craft.'
where slug = 'tech-media';

update ministries set duties = array[
  'Get there before everyone else and pray over the room',
  'Welcome people at the door, especially anyone on their own',
  'Seat latecomers without making them feel late',
  'Count the offering with a second person present',
  'Notice who has stopped coming and tell a leader'
] where slug = 'ushering';

update ministries set duties = array[
  'Rehearse midweek, not just before the service',
  'Know the songs well enough to look up from the music',
  'Keep the keys where an ordinary voice can reach',
  'Play for the room, not for yourself',
  'Stay accountable to a leader for how you live, not only how you play'
] where slug = 'worship';

update ministries set duties = array[
  'Take a turn on sound, slides, or the livestream',
  'Come early for soundcheck and stay to pack down',
  'Grab photos and clips for the feed and the page',
  'Look after the gear and keep the cables tidy',
  'Teach someone else so you are not the only one who knows how'
] where slug = 'tech-media';

-- ---------- 20260911_ministry_membership.sql ----------
-- Turn ministry interest into a small lifecycle, and let admins assign a leader
-- to each ministry.
--
-- Interest and membership are the same relationship at different stages, not
-- two tables. Keeping one row per person per ministry means a member who is
-- stood down does not reappear in the interested list, and nobody is ever
-- counted twice.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'ministry_status') then
    create type public.ministry_status as enum ('interested', 'member', 'declined');
  end if;
end $$;

alter table public.ministry_interests
  add column if not exists status      public.ministry_status not null default 'interested',
  add column if not exists decided_at  timestamptz,
  add column if not exists decided_by  uuid references public.profiles(id) on delete set null,
  add column if not exists role_in_team text;

comment on column public.ministry_interests.status is
  'interested: put their hand up. member: serving. declined: not this season.';
comment on column public.ministry_interests.role_in_team is
  'Optional, e.g. "Sound" or "Front door". Shown beside the name on the team list.';

create index if not exists ministry_interests_status_idx
  on public.ministry_interests (ministry_id, status);

-- ---------------------------------------------------------------------------
-- Who may change a status
--
-- Only the ministry's own leader, or staff. A member can still withdraw their
-- own interest entirely, which is the delete policy already in place, but they
-- must not be able to promote themselves onto a team.
-- ---------------------------------------------------------------------------

create or replace function public.can_manage_ministry(m_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select is_staff()
      or exists (select 1 from public.ministries m
                 where m.id = m_id and m.leader_id = auth.uid());
$$;

revoke all on function public.can_manage_ministry(uuid) from public;
grant execute on function public.can_manage_ministry(uuid) to authenticated;

drop policy if exists "leaders decide ministry membership" on public.ministry_interests;
create policy "leaders decide ministry membership"
  on public.ministry_interests for update
  using (can_manage_ministry(ministry_id))
  with check (can_manage_ministry(ministry_id));

grant update on public.ministry_interests to authenticated;

-- ---------------------------------------------------------------------------
-- Who is on a team is not a secret
--
-- The interested list stays private to the ministry's leaders, because putting
-- your hand up is a tentative thing and should not be public. Serving on a team
-- is the opposite: the congregation should know who is on the sound desk. This
-- function exposes only confirmed members.
-- ---------------------------------------------------------------------------

create or replace function public.ministry_team(m_id uuid)
returns table (
  profile_id uuid,
  full_name  text,
  avatar_url text,
  role_in_team text
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.avatar_url, mi.role_in_team
  from public.ministry_interests mi
  join public.profiles p on p.id = mi.profile_id
  where mi.ministry_id = m_id
    and mi.status = 'member'
    and p.account_status = 'approved'
  order by p.full_name;
$$;

revoke all on function public.ministry_team(uuid) from public;
grant execute on function public.ministry_team(uuid) to authenticated;

-- One call for the listing page, so it does not query per ministry.
create or replace function public.ministry_teams()
returns table (
  ministry_id uuid,
  profile_id  uuid,
  full_name   text,
  avatar_url  text,
  role_in_team text
)
language sql
security definer
set search_path = public
stable
as $$
  select mi.ministry_id, p.id, p.full_name, p.avatar_url, mi.role_in_team
  from public.ministry_interests mi
  join public.profiles p on p.id = mi.profile_id
  where mi.status = 'member'
    and p.account_status = 'approved'
  order by p.full_name;
$$;

revoke all on function public.ministry_teams() from public;
grant execute on function public.ministry_teams() to authenticated;

-- ---------- 20260911_profile_social_links.sql ----------
-- Social and contact details on member profiles.
--
-- contact_number already existed but was never shown anywhere. These columns
-- make a profile something other members can actually reach, and add an
-- explicit opt-in before a phone number is visible to anyone but staff.

alter table public.profiles
  add column if not exists facebook_url  text,
  add column if not exists instagram_url text,
  -- A phone number is the most sensitive field here, so it stays private until
  -- the member deliberately turns it on. Defaulting this to true would publish
  -- every existing number the moment this migration ran.
  add column if not exists show_contact  boolean not null default false;

-- Store whole URLs, not handles, so the UI never has to guess which network a
-- bare string belongs to. Empty strings are rejected rather than stored as a
-- value that looks present but renders as a broken link.
alter table public.profiles
  drop constraint if exists profiles_facebook_url_check;
alter table public.profiles
  add constraint profiles_facebook_url_check
  check (facebook_url is null or facebook_url ~* '^https://([a-z0-9-]+\.)*facebook\.com/.+');

alter table public.profiles
  drop constraint if exists profiles_instagram_url_check;
alter table public.profiles
  add constraint profiles_instagram_url_check
  check (instagram_url is null or instagram_url ~* '^https://([a-z0-9-]+\.)*instagram\.com/.+');

comment on column public.profiles.facebook_url  is 'Full https URL to the member''s Facebook profile.';
comment on column public.profiles.instagram_url is 'Full https URL to the member''s Instagram profile.';
comment on column public.profiles.show_contact  is 'Member opt-in to showing contact_number to other members.';

-- ---------- 20260911_signup_leader_choice.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Let members pick a leader when they sign up, and tell the leaders when
-- somebody arrives without one.
--
-- All of this lives in the database rather than in the signup page because a
-- person signing up is not authenticated yet. Their browser cannot read the
-- leader list or write a notification without RLS refusing it, so the work is
-- done by a security-definer trigger that runs as the account is created.

-- 1. A notification kind for "this member has no leader".
alter type public.notification_kind add value if not exists 'unassigned_member';

-- 2. A public, deliberately narrow view of who the leaders are.
--    Signup is unauthenticated, so this returns names and ids only. No email,
--    no phone, no role. It is the minimum needed to populate a dropdown.
create or replace function public.list_leaders()
returns table (id uuid, full_name text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name
  from public.profiles p
  where p.is_leader = true
    and p.account_status = 'approved'
  order by p.full_name;
$$;

revoke all on function public.list_leaders() from public;
grant execute on function public.list_leaders() to anon, authenticated;

-- 3. Carry the chosen leader through signup, and raise the alarm when there
--    isn't one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_leader uuid;
  leader_row    record;
begin
  -- The signup form puts this in user metadata. It is text coming from a
  -- browser, so a value that is not a uuid is treated as no choice at all
  -- rather than being allowed to abort account creation.
  begin
    chosen_leader := nullif(new.raw_user_meta_data->>'leader_id', '')::uuid;
  exception when others then
    chosen_leader := null;
  end;

  -- Only accept a leader who actually is one. Anyone can put anything in
  -- metadata, so this is validated rather than trusted.
  if chosen_leader is not null then
    if not exists (
      select 1 from public.profiles
      where id = chosen_leader and is_leader = true and account_status = 'approved'
    ) then
      chosen_leader := null;
    end if;
  end if;

  insert into public.profiles (id, full_name, email, leader_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    chosen_leader
  )
  on conflict (id) do nothing;

  -- No leader chosen: tell every leader, so that whoever is free can pick the
  -- new member up. One row each rather than one shared row, because the
  -- notification bell is per user and each leader reads and dismisses it
  -- independently.
  if chosen_leader is null then
    for leader_row in
      select id from public.profiles
      where is_leader = true and account_status = 'approved'
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (
        leader_row.id,
        new.id,
        'unassigned_member',
        'profile',
        new.id,
        jsonb_build_object(
          'full_name', coalesce(new.raw_user_meta_data->>'full_name', new.email),
          'email', new.email
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ---------- 20260911_signup_phone_and_events.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- A phone number at signup, and an interested button on events.

-- ---------------------------------------------------------------------------
-- 1. Phone number at signup
--
-- Required on the form rather than enforced with NOT NULL, because existing
-- members signed up without one and a constraint would lock them out of their
-- own profile the next time they saved it. New accounts carry it through from
-- the form in the same transaction as the account.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_leader uuid;
  leader_row    record;
  agreed        text;
  phone         text;
begin
  begin
    chosen_leader := nullif(new.raw_user_meta_data->>'leader_id', '')::uuid;
  exception when others then
    chosen_leader := null;
  end;

  if chosen_leader is not null then
    if not exists (
      select 1 from public.profiles
      where id = chosen_leader and is_leader = true and account_status = 'approved'
    ) then
      chosen_leader := null;
    end if;
  end if;

  agreed := nullif(new.raw_user_meta_data->>'terms_accepted_version', '');
  phone  := nullif(trim(new.raw_user_meta_data->>'contact_number'), '');

  insert into public.profiles (
    id, full_name, email, leader_id, contact_number,
    terms_accepted_version, terms_accepted_at
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    chosen_leader,
    phone,
    agreed,
    case when agreed is not null then now() end
  )
  on conflict (id) do nothing;

  if chosen_leader is null then
    for leader_row in
      select id from public.profiles
      where is_leader = true and account_status = 'approved' and is_hidden = false
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (
        leader_row.id, new.id, 'unassigned_member', 'profile', new.id,
        jsonb_build_object(
          'full_name', coalesce(new.raw_user_meta_data->>'full_name', new.email),
          'email', new.email
        )
      );
    end loop;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Who is coming to an event
-- ---------------------------------------------------------------------------

create table if not exists public.event_interests (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, profile_id)
);

create index if not exists event_interests_event_idx
  on public.event_interests (event_id, created_at desc);

alter table public.event_interests enable row level security;

drop policy if exists "members mark themselves interested" on public.event_interests;
create policy "members mark themselves interested"
  on public.event_interests for insert
  with check (profile_id = auth.uid() and is_approved());

drop policy if exists "members withdraw their own interest" on public.event_interests;
create policy "members withdraw their own interest"
  on public.event_interests for delete
  using (profile_id = auth.uid());

-- Unlike a ministry, who is coming to an event is not sensitive. Knowing that
-- other people are going is most of the reason anyone decides to go, so every
-- approved member can see the list.
drop policy if exists "members see who is coming" on public.event_interests;
create policy "members see who is coming"
  on public.event_interests for select
  using (is_approved() or is_staff());

grant select, insert, delete on public.event_interests to authenticated;

alter type public.notification_kind add value if not exists 'event_interest';

-- The event's creator hears about it if they are a leader; otherwise every
-- leader does, so somebody is actually counting heads.
create or replace function public.notify_event_interest()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e         record;
  who       text;
  recipient record;
begin
  select title, created_by into e from public.events where id = new.event_id;
  select full_name into who from public.profiles where id = new.profile_id;

  for recipient in
    select id from public.profiles
    where is_leader = true and account_status = 'approved' and is_hidden = false
      and id <> new.profile_id
  loop
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (recipient.id, new.profile_id, 'event_interest', 'event', new.event_id,
            jsonb_build_object('full_name', who, 'title', e.title));
  end loop;

  return new;
end;
$$;

drop trigger if exists on_event_interest on public.event_interests;
create trigger on_event_interest
  after insert on public.event_interests
  for each row execute function public.notify_event_interest();

-- Ministries go back behind a member account. The public menu is Home, News,
-- Events and Live only.
drop policy if exists "anyone can read active ministries" on public.ministries;
create policy "members read active ministries"
  on public.ministries for select
  using ((is_active = true and is_approved()) or is_staff());

revoke select on public.ministries from anon;

-- ---------- 20260912_book_order.sql ----------
-- Canonical book order and testament.
--
-- Stored rather than derived so verses can be listed in Bible order without the
-- application knowing the sequence, and so a query can filter by testament
-- without a list of names in the WHERE clause.
--
-- The names match what the import writes, which is bible-api.com's spelling.
-- Note Psalms rather than Psalm: the API uses the plural, and mixing the two
-- silently splits the book in two.

create table if not exists public.bible_books (
  name       text primary key,
  book_order smallint not null unique,
  testament  text not null check (testament in ('OT', 'NT')),
  chapters   smallint not null
);

insert into public.bible_books (name, book_order, testament, chapters) values
('Genesis',1,'OT',50),('Exodus',2,'OT',40),('Leviticus',3,'OT',27),('Numbers',4,'OT',36),
('Deuteronomy',5,'OT',34),('Joshua',6,'OT',24),('Judges',7,'OT',21),('Ruth',8,'OT',4),
('1 Samuel',9,'OT',31),('2 Samuel',10,'OT',24),('1 Kings',11,'OT',22),('2 Kings',12,'OT',25),
('1 Chronicles',13,'OT',29),('2 Chronicles',14,'OT',36),('Ezra',15,'OT',10),('Nehemiah',16,'OT',13),
('Esther',17,'OT',10),('Job',18,'OT',42),('Psalms',19,'OT',150),('Proverbs',20,'OT',31),
('Ecclesiastes',21,'OT',12),('Song of Solomon',22,'OT',8),('Isaiah',23,'OT',66),('Jeremiah',24,'OT',52),
('Lamentations',25,'OT',5),('Ezekiel',26,'OT',48),('Daniel',27,'OT',12),('Hosea',28,'OT',14),
('Joel',29,'OT',3),('Amos',30,'OT',9),('Obadiah',31,'OT',1),('Jonah',32,'OT',4),
('Micah',33,'OT',7),('Nahum',34,'OT',3),('Habakkuk',35,'OT',3),('Zephaniah',36,'OT',3),
('Haggai',37,'OT',2),('Zechariah',38,'OT',14),('Malachi',39,'OT',4),
('Matthew',40,'NT',28),('Mark',41,'NT',16),('Luke',42,'NT',24),('John',43,'NT',21),
('Acts',44,'NT',28),('Romans',45,'NT',16),('1 Corinthians',46,'NT',16),('2 Corinthians',47,'NT',13),
('Galatians',48,'NT',6),('Ephesians',49,'NT',6),('Philippians',50,'NT',4),('Colossians',51,'NT',4),
('1 Thessalonians',52,'NT',5),('2 Thessalonians',53,'NT',3),('1 Timothy',54,'NT',6),('2 Timothy',55,'NT',4),
('Titus',56,'NT',3),('Philemon',57,'NT',1),('Hebrews',58,'NT',13),('James',59,'NT',5),
('1 Peter',60,'NT',5),('2 Peter',61,'NT',3),('1 John',62,'NT',5),('2 John',63,'NT',1),
('3 John',64,'NT',1),('Jude',65,'NT',1),('Revelation',66,'NT',22)
on conflict (name) do nothing;

update public.daily_verses v
set book_order = b.book_order, testament = b.testament
from public.bible_books b
where b.name = v.book and (v.book_order is null or v.testament is null);

-- Only the 66 canonical books may be stored, checked against the table rather
-- than against a regular expression that would accept Hezekiah.
alter table public.daily_verses drop constraint if exists verse_book_is_canonical;
alter table public.daily_verses
  add constraint verse_book_is_canonical
  foreign key (book) references public.bible_books(name);

-- ---------- 20260912_claim_pairing.sql ----------
-- Claim a verse and a general reminder as a pairing.
--
-- The unit of content is the pairing, so the supply is verses multiplied by
-- reminders rather than the count of either. A reminder is reusable across
-- different verses but never twice under the same verse, and never twice for
-- the same person, which is what keeps it feeling chosen rather than rotated.
create or replace function public.claim_daily_content(p_user uuid, p_day date)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  r_id     uuid;
  r_theme  text;
  attempts int := 0;
  made     uuid;
begin
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      -- A verse that reads as a devotional thought, still free today, and not
      -- one this person has already had.
      select v.id into v_id
      from public.daily_verses v
      where v.status = 'active'
        and v.devotional = true
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.verse_id = v.id
        )
        and not exists (
          select 1 from public.daily_assignments a
          where a.user_id = p_user and a.verse_id = v.id
        )
      -- Random rather than least-recently-used: with tens of thousands of
      -- verses, ordering by last use would sort the entire table on every
      -- request for no benefit anyone can perceive.
      order by random()
      limit 1;

      -- Nothing unseen left for this person; allow a verse they have had
      -- before, since the reminder under it will still be new to them.
      if v_id is null then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and v.devotional = true
          and not exists (
            select 1 from public.daily_assignments a
            where a.assigned_on = p_day and a.verse_id = v.id
          )
        order by random()
        limit 1;
      end if;

      exit when v_id is null;

      -- A reminder never paired with this verse, and never seen by this person.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.status = 'active'
        and not exists (
          select 1 from public.daily_assignments a
          where a.verse_id = v_id and a.reminder_id = r.id
        )
        and not exists (
          select 1 from public.daily_assignments a
          where a.user_id = p_user and a.reminder_id = r.id
        )
      order by random()
      limit 1;

      -- This verse has no reminder left that works for this reader. Try a
      -- different verse rather than giving up.
      continue when r_id is null;

      insert into public.daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, v_id, r_id, p_day, r_theme)
      on conflict do nothing
      returning id into made;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, r.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;

-- ---------- 20260912_claim_per_reader.sql ----------
-- Per-reader daily assignment, for members and visitors alike.
--
-- There is no global verse of the day. Two readers may hold the same verse
-- today; what they may never share is a reminder, which is enforced by a unique
-- index on reminder_id rather than by anything in application code.
--
-- Races are handled by writing first and reacting to the conflict, not by
-- checking first and hoping. Every insert is ON CONFLICT DO NOTHING; a lost
-- race returns no row and the loop tries again with a different reminder or a
-- different verse. On the identity conflict the winning row is simply read back.

-- Old signatures return a different row shape, so they are dropped rather than
-- replaced. Postgres refuses to change the return type of an existing function.
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
drop function if exists public.claim_daily_content(uuid, date);

create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  focus_tag     text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  r_id      uuid;
  r_theme   text;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  -- Already assigned today: hand back the same row on every refresh.
  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      if is_member then
        -- Members draw from everything imported that reads as a devotional
        -- thought, and from verses they have not already had where possible.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random()
          limit 1;
        end if;
      else
        -- Visitors only ever meet the welcoming themes. There is deliberately
        -- no fallback to an untagged verse: somebody's first encounter with
        -- this church should not be a random passage from Judges.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1
            from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1
              from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random()
          limit 1;
        end if;
      end if;

      exit when v_id is null;

      -- An unspent reminder for that verse. Reminders are written per verse, so
      -- this is the pool that has to hold out.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.status = 'active'
        and r.verse_id = v_id
        and not exists (
          select 1 from public.daily_assignments a where a.reminder_id = r.id
        )
      order by random()
      limit 1;

      -- No unspent reminder for this verse: make one from a template that has
      -- not been used here before. Returns null once every template has been
      -- used for this verse, in which case try a different verse.
      if r_id is null then
        r_id := public.generate_reminder_for(v_id);
        continue when r_id is null;
        select dr.theme into r_theme from public.daily_reminders dr where dr.id = r_id;
      end if;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, r_id, p_day, coalesce(r_theme, 'general'))
      on conflict do nothing
      returning id into made;

      if made is null then
        -- Either somebody took that reminder, or a concurrent request for this
        -- same reader already created today's row. Check the second case before
        -- drawing again, so a refresh never produces two assignments.
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, r.reminder, r.focus_tag, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

-- Signed-in readers. auth.uid() is taken from the token, so a caller cannot ask
-- for somebody else's assignment.
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid, verse_ref text, verse_text text, reminder text,
  focus_tag text, theme text, assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    auth.uid(), null, (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;

-- Visitors. The id comes from a server-set HttpOnly cookie, never from the page.
create or replace function public.visitor_daily_content(p_visitor uuid)
returns table (
  assignment_id uuid, verse_ref text, verse_text text, reminder text,
  focus_tag text, theme text, assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    null, p_visitor, (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.visitor_daily_content(uuid) from public;
grant execute on function public.visitor_daily_content(uuid) to anon, authenticated;

-- ---------- 20260912_daily_reminders_split.sql ----------
-- Separate the verse from its reminder.
--
-- The first version stored a verse and a reminder together as one pool row,
-- which meant a verse could only ever carry one reminder. When the same verse
-- came round again, for a different person or on a later day, it arrived with
-- exactly the same words attached. A verse should be able to speak to several
-- situations, so reminders now belong to a verse and a verse has many.
--
-- WHAT IS GUARANTEED NOW
--
--   A reminder is used once, ever.        unique index on (reminder_id)
--   No two people share a verse in a day. unique index on (assigned_on, verse_id)
--   One assignment per person per day.    unique index on (user_id, assigned_on)
--
-- The first of those is what this migration is for: because a reminder can
-- never be reused, a repeated verse necessarily arrives with different words.

create table if not exists public.daily_verses (
  id         uuid primary key default gen_random_uuid(),
  reference  text not null,
  verse_text text not null,
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  reference_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reference), '[^a-z0-9: ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  constraint verse_reference_is_real check (public.is_valid_bible_reference(reference)),
  constraint verse_no_em_dash check (verse_text !~ '[—–]')
);

create unique index if not exists daily_verses_reference_uniq on public.daily_verses (reference_norm);

create table if not exists public.daily_reminders (
  id         uuid primary key default gen_random_uuid(),
  verse_id   uuid not null references public.daily_verses(id) on delete cascade,
  reminder   text not null,
  theme      text not null,
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  reminder_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  constraint reminder_length check (
    array_length(regexp_split_to_array(trim(reminder), '\s+'), 1) between 50 and 90
  ),
  constraint reminder_no_em_dash check (reminder !~ '[—–]'),
  constraint reminder_no_emoji check (reminder ~ '^[\x00-\x7F''’"“”]*$'),
  constraint reminder_no_hashtag check (reminder !~ '#')
);

create unique index if not exists daily_reminders_norm_uniq on public.daily_reminders (reminder_norm);
create index if not exists daily_reminders_verse_idx on public.daily_reminders (verse_id) where status = 'active';
create index if not exists daily_reminders_trgm on public.daily_reminders using gin (reminder_norm gin_trgm_ops);

-- Near duplicates refused on write, comparing against new.reminder directly
-- because a stored generated column is not populated until after this runs.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  candidate_norm text;
  clash record;
begin
  candidate_norm := trim(regexp_replace(
    regexp_replace(lower(new.reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));

  select id, similarity(reminder_norm, candidate_norm) as score
    into clash
  from public.daily_reminders
  where id <> new.id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to existing reminder %',
      round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists daily_reminders_similarity on public.daily_reminders;
create trigger daily_reminders_similarity
  before insert or update of reminder on public.daily_reminders
  for each row execute function public.reject_similar_reminder();

-- ---------------------------------------------------------------------------
-- Carry the existing pool across, then rebuild the assignments table around
-- the two new keys.
-- ---------------------------------------------------------------------------

insert into public.daily_verses (reference, verse_text)
select distinct on (verse_ref) verse_ref, verse_text
from public.daily_content
on conflict do nothing;

insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, c.reminder, c.theme
from public.daily_content c
join public.daily_verses v on v.reference = c.verse_ref
on conflict do nothing;

drop table if exists public.daily_assignments cascade;

create table public.daily_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  verse_id    uuid not null references public.daily_verses(id)    on delete restrict,
  reminder_id uuid not null references public.daily_reminders(id) on delete restrict,
  assigned_on date not null,
  theme       text not null,
  status      text not null default 'active' check (status in ('active', 'superseded')),
  created_at  timestamptz not null default now(),

  constraint one_per_user_per_day unique (user_id, assigned_on),
  constraint one_verse_per_day    unique (assigned_on, verse_id),
  -- A reminder is spent once and never comes back, which is what makes a
  -- repeated verse arrive with new words.
  constraint reminder_used_once   unique (reminder_id)
);

create index daily_assignments_user_idx  on public.daily_assignments (user_id, assigned_on desc);
create index daily_assignments_verse_idx on public.daily_assignments (verse_id, assigned_on desc);

alter table public.daily_verses     enable row level security;
alter table public.daily_reminders  enable row level security;
alter table public.daily_assignments enable row level security;

drop policy if exists "assignments are private" on public.daily_assignments;
create policy "assignments are private"
  on public.daily_assignments for select using (user_id = auth.uid());

grant select on public.daily_assignments to authenticated;

drop table if exists public.daily_content cascade;
-- Claim a verse and, separately, a reminder belonging to that verse.
--
-- The reminder is chosen from the ones attached to the chosen verse that have
-- never been used by anybody. Because reminder_used_once makes a reminder
-- unrepeatable, a verse seen a second time necessarily arrives with different
-- words. A verse with no unused reminders left is skipped entirely rather than
-- being shown with a repeat.
create or replace function public.claim_daily_content(p_user uuid, p_day date)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  r_id     uuid;
  r_theme  text;
  attempts int := 0;
  made     uuid;
begin
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      -- A verse still free today that has at least one unused reminder.
      select v.id into v_id
      from public.daily_verses v
      where v.status = 'active'
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.verse_id = v.id
        )
        and exists (
          select 1 from public.daily_reminders r
          where r.verse_id = v.id and r.status = 'active'
            and not exists (select 1 from public.daily_assignments a2 where a2.reminder_id = r.id)
        )
      order by
        -- Prefer a verse this person has not had before.
        (exists (select 1 from public.daily_assignments a
                 where a.user_id = p_user and a.verse_id = v.id)),
        -- Then whatever has gone longest unused by anyone.
        coalesce((select max(a.assigned_on) from public.daily_assignments a
                  where a.verse_id = v.id), date '1970-01-01'),
        md5(v.id::text || p_day::text)
      limit 1;

      exit when v_id is null;

      -- An unused reminder for that verse. Fresh words every time the verse
      -- appears, which is the whole point of the split.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.verse_id = v_id and r.status = 'active'
        and not exists (select 1 from public.daily_assignments a where a.reminder_id = r.id)
      order by md5(r.id::text || p_user::text || p_day::text)
      limit 1;

      continue when r_id is null;

      insert into public.daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, v_id, r_id, p_day, r_theme)
      on conflict do nothing
      returning id into made;

      exit when made is not null;
      -- Lost a race on the verse or the reminder. Go round again.
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, r.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;
insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, r.reminder, r.theme from public.daily_verses v
join (values
('Zephaniah 3:17','Think about how you talk to yourself when you get something wrong. Most of us are far harsher than we would ever be with a friend. God is not adding his voice to that pile. He looks at you the way a parent looks at a child asleep in the back of the car. Tired, imperfect, and completely theirs. Let that be the last thing you hear tonight.','God''s love'),
('Isaiah 41:10','Fear tends to arrive loudest at about two in the morning, when nothing can actually be done. If that is where you are, you are not weak for lying awake. Say the worry out loud, name it properly, and then hand it over until morning. God is awake anyway. You are allowed to stop guarding the situation for a few hours and sleep.','Courage when facing fear'),
('Lamentations 3:22-23','Some seasons feel like one long repeat of the same mistake. You apologise, you mean it, and a fortnight later you are back. God is not keeping a tally that runs out. His patience is not a limited supply you have been drawing down since childhood. Get up again today. Not with shame driving you, but because there is genuinely more mercy waiting.','Forgiveness and grace'),
('Matthew 11:28','There is a difference between being busy and being weighed down. Busy passes. Weighed down follows you into the evening and sits on your chest. If that is you, work out what you are actually carrying, because it is rarely only the diary. Bring the real thing to God, and let somebody help you with a piece of it this week.','Rest when feeling tired'),
('Psalm 27:14','The hardest part of waiting is not knowing whether anything is happening. You want a sign that the situation is moving. Often there is none, and you have to decide to keep showing up anyway. That decision is not naive. It is courage of a quiet kind, and God sees it even when nobody else notices you are still standing there.','Hope while waiting'),
('Philippians 4:6-7','Money worries have a particular way of taking over. They follow you into the shower and the commute and the middle of a conversation. If the numbers are not working this month, God is not disappointed in you for it. Tell him exactly what the shortfall is. Then tell one person you trust, because carrying a financial fear alone makes it heavier than it is.','Peace during stressful moments'),
('Proverbs 3:5-6','You might be second-guessing a choice you already made. Turning it over does not change it, and replaying it only wears you out. If you asked honestly and chose with what you knew at the time, you did the thing you were meant to do. God can work with a decision that turns out imperfectly. He has done it with every person who ever followed him.','Trusting God''s direction'),
('Joshua 1:9','Sometimes the brave thing is very small. Sending the message. Booking the appointment. Walking into a room where you do not know anyone. Nobody will applaud any of it, and it will still cost you something. God is with you in the small brave things just as much as the large ones, and today probably only asks for one of the small ones.','Strength during difficult times'),
('Psalm 34:18','If somebody you love is struggling and you cannot fix it, that helplessness is its own ache. You want to do something useful and there is nothing to do. Sitting with them is not nothing. It is most of what love looks like when there is no solution. God does the same for you, and he is close to them too.','Healing and comfort'),
('Galatians 6:9','There is a kind of tiredness that comes from caring about something nobody else seems to care about. You keep turning up and it keeps looking the same. Rest properly, then decide again. Not because giving up would be wrong, but because the thing you are doing is worth more than it currently looks, and you may be closer than you think.','Perseverance after disappointment'),
('James 1:5','Wisdom often arrives as a slow narrowing rather than a bright idea. You rule something out, then something else, and eventually one option is left that you can live with. That is God guiding you just as much as any dramatic moment would be. Give yourself permission to take the boring, sensible route. It is usually the one that holds.','Wisdom and guidance'),
('1 Thessalonians 5:16-18','Try noticing one thing today that you would normally walk straight past. The way the light came through the window. Someone letting you go first. A meal you did not have to worry about paying for. None of that fixes what is hard, and it is not meant to. It simply reminds you that good things are still arriving, unearned, all the time.','Gratitude')
) as r(ref, reminder, theme) on v.reference = r.ref;
insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, r.reminder, r.theme from public.daily_verses v
join (values
('Romans 8:28','You may be looking back at a stretch of your life that felt pointless at the time. The job that went nowhere, the years that seemed wasted. God does not discard those. People who have been through something difficult tend to be the ones others can actually talk to. What felt like a detour often turns out to be the reason someone trusts you later.','Purpose and faith'),
('Psalm 46:10','Your phone is very good at making you feel responsible for things happening a long way away. Some of that concern is right and most of it is simply noise you cannot act on. Put it down for an hour this evening. The world will keep turning without your attention on it, which is a relief rather than an insult.','Peace during stressful moments'),
('Isaiah 40:31','Recovery from anything, illness or burnout or grief, is rarely a straight line. You have a good week and then a bad afternoon and assume you are back where you started. You are not. Progress that dips is still progress. Judge it over months rather than days, and be as patient with yourself as you would be with anyone else.','Strength during difficult times'),
('Ephesians 4:32','Being kind is easiest with people who are easy. The test is the relative who always says the wrong thing, or the colleague who takes credit. You do not have to feel warm towards them to treat them decently. Start with not repeating the story about them, and see how much lighter the next conversation feels.','Forgiveness and grace'),
('1 Peter 5:7','Parents carry a specific worry that never fully switches off, even when everyone is safely asleep. If that is you, you are not failing because you cannot stop thinking about it. You cannot control every outcome, and you were never meant to. Hand the ones you love back to God tonight. He is more invested in them than you are.','Peace during stressful moments'),
('Colossians 3:23','If you are between jobs, or in one that is well below what you can do, that is a wearing place to be. Your worth is not set by a job title and it never was. Do today''s work properly, keep looking, and let somebody help. God is not measuring your value by your payslip, and you should not either.','Purpose and faith'),
('Psalm 73:26','Chronic pain or a long illness wears down faith in a way that sudden crisis does not. There is no dramatic moment, only the daily grind of it. If you have stopped being able to pray in sentences, that is fine. God is not waiting for eloquence. Being present and still breathing is a form of holding on.','Healing and comfort'),
('Romans 12:12','There is a conversation you have been rehearsing for weeks. It may go badly. It may also go far better than the version in your head, because the version in your head assumes the worst. Wait until you are calm rather than until you feel ready, because ready may not come. Then say the true thing kindly.','Patience'),
('John 14:27','A house can be quiet and still not be peaceful. If things are tense at home, you probably feel it in your shoulders before you notice it in your thoughts. Peace does not mean pretending everything is fine. It might start with one honest sentence, said gently, at a moment when nobody is already angry.','Peace during stressful moments'),
('Deuteronomy 31:8','Moving somewhere new strips away all the small things that made you feel competent. You do not know the roads, the shops, or anyone''s name. That disorientation is normal and it does pass. God is not only in the place you left. He is already in the new one, in people you have not met yet.','Courage when facing fear'),
('Psalm 121:1-2','When you are the one everybody leans on, it is easy to forget that you are allowed to need help too. Being capable is not the same as being fine. Ask somebody for something this week, even something small. Letting yourself be helped is part of what keeps you able to help anyone else.','Trusting God''s direction'),
('2 Corinthians 12:9','There is something about yourself you would change if you could. A temper, an anxiety, a limitation you did not choose. God is not waiting for you to fix it before he can use you. Some of the most genuine people you know are genuine precisely because they stopped pretending. You are allowed to be a work in progress.','God''s love')
) as r(ref, reminder, theme) on v.reference = r.ref;

-- ---------- 20260912_devotional_safety.sql ----------
-- Restrict which verses can be drawn as a daily reading.
--
-- WHY THIS EXISTS
--
-- Drawing uniformly across all 27,475 verses looks correct and is not. A test
-- run of ten member draws returned Genesis 34:18 and Genesis 19:36, which sit
-- in the accounts of the rape of Dinah and of Lot's daughters. Those are
-- Scripture and they are in the Bible for a reason, but a church website that
-- greets someone with them on a Tuesday morning has done real harm, and no
-- amount of technical correctness makes up for it.
--
-- The earlier heuristic only screened out genealogies, measurements and short
-- fragments. It had no view on narrative content at all.
--
-- WHAT THIS DOES
--
-- Eligibility becomes an allowlist by book rather than a blocklist by phrase. A
-- blocklist has to anticipate every distressing passage, and it will always
-- miss some. An allowlist is wrong only in being conservative, which is the
-- right direction to be wrong in here.
--
-- The pool is still large: the wisdom and prophetic books, the Gospels and the
-- Epistles come to roughly ten thousand verses. Narrative history stays in the
-- database and remains readable elsewhere; it simply is not drawn at random and
-- handed to somebody as their word for the day.
--
-- TO WIDEN IT: add books to devotional_books below, or tag individual verses
-- from any book with a topic, which makes them eligible regardless of book.

create table if not exists public.devotional_books (
  name text primary key references public.bible_books(name)
);

insert into public.devotional_books (name) values
  -- Wisdom and worship
  ('Psalms'), ('Proverbs'), ('Ecclesiastes'),
  -- Prophets, which are largely addressed to the reader
  ('Isaiah'), ('Jeremiah'), ('Lamentations'), ('Hosea'), ('Joel'), ('Amos'),
  ('Obadiah'), ('Jonah'), ('Micah'), ('Nahum'), ('Habakkuk'), ('Zephaniah'),
  ('Haggai'), ('Zechariah'), ('Malachi'),
  -- Gospels
  ('Matthew'), ('Mark'), ('Luke'), ('John'),
  -- Letters, which are written as direct address
  ('Romans'), ('1 Corinthians'), ('2 Corinthians'), ('Galatians'), ('Ephesians'),
  ('Philippians'), ('Colossians'), ('1 Thessalonians'), ('2 Thessalonians'),
  ('1 Timothy'), ('2 Timothy'), ('Titus'), ('Philemon'), ('Hebrews'), ('James'),
  ('1 Peter'), ('2 Peter'), ('1 John'), ('2 John'), ('3 John'), ('Jude')
on conflict (name) do nothing;

-- Recompute eligibility. A verse qualifies if it is in an allowed book and
-- already passed the earlier structural screening, or if it has been
-- deliberately tagged with a topic by a person.
update public.daily_verses v
set devotional = (
  (exists (select 1 from public.devotional_books d where d.name = v.book) and v.devotional)
  or exists (select 1 from public.verse_topics vt where vt.verse_id = v.id)
);

-- Even inside allowed books some passages are graphic or are curses. Screening
-- by content is a blunt instrument and is applied only as a second pass on top
-- of the allowlist, never as the only defence.
update public.daily_verses
set devotional = false
where devotional
  and verse_text ~* '\m(rape|raped|ravish|concubine|slaughter|disembowel|dash(ed)? .{0,20}(pieces|rocks)|rip(ped)? open|bloodshed|harlot|whore|adulteress)\M';

-- Anything very short or very long does not stand alone as a daily reading.
update public.daily_verses
set devotional = false
where devotional
  and (array_length(regexp_split_to_array(trim(verse_text), '\s+'), 1) < 10
       or array_length(regexp_split_to_array(trim(verse_text), '\s+'), 1) > 70);

-- ---------- 20260912_drop_word_count.sql ----------
-- Stop counting words.
--
-- The 50 to 90 word rule was mine, not a requirement, and it was doing harm. It
-- rejected four perfectly good reminders for being 44 to 49 words, and earlier
-- it pushed me into stitching two fragments together to pad a reminder up to
-- length, which is what produced the ungrammatical text. A reminder should be
-- as long as the thought needs and no longer.
--
-- The checks that remain are the ones about quality rather than quantity:
-- it must start with a capital, end with proper punctuation, avoid em dashes
-- and emoji, avoid hashtags, avoid assuming who is reading, and not repeat
-- something already written for the same verse.

alter table public.reminder_templates drop constraint if exists template_length;
alter table public.daily_reminders    drop constraint if exists reminder_length;

-- Grammar rules now apply to stored reminders too, not just to templates. A
-- reminder is what somebody actually reads, so it is the thing worth checking.
alter table public.daily_reminders drop constraint if exists reminder_starts_capital;
alter table public.daily_reminders
  add constraint reminder_starts_capital check (reminder ~ '^[A-Z]');

alter table public.daily_reminders drop constraint if exists reminder_ends_stop;
alter table public.daily_reminders
  add constraint reminder_ends_stop check (reminder ~ '[.!?]$');

-- No double spaces, and no lowercase word starting a new sentence, which is the
-- signature of text that was joined together rather than written.
alter table public.daily_reminders drop constraint if exists reminder_clean_spacing;
alter table public.daily_reminders
  add constraint reminder_clean_spacing check (reminder !~ '  ' and reminder !~ '[.!?] +[a-z]');

alter table public.reminder_templates drop constraint if exists template_clean_spacing;
alter table public.reminder_templates
  add constraint template_clean_spacing check (text !~ '  ' and text !~ '[.!?] +[a-z]');

-- ---------- 20260912_general_reminder_pool.sql ----------
-- Reminders that assume something about the reader are removed and replaced.
--
-- The old set guessed at circumstances: that you are a parent, that you have a
-- job, that you are ill, that you are grieving. When the guess is wrong the
-- message stops feeling personal and starts feeling awkward, which is the
-- opposite of the intent. These speak to what everyone actually has in common:
-- worry, tiredness, waiting, regret, and needing to be told you are not alone.

delete from public.daily_reminders;

insert into public.daily_reminders (reminder, theme) values
('There is something you have been turning over for a while now, and it has not resolved itself. You are allowed to bring it to God exactly as it is, unfinished and unclear. You do not need better words for it. Being honest about what is heavy is not a lack of faith. It is the beginning of putting it somewhere other than your own shoulders.', 'Peace during stressful moments'),
('You are probably harder on yourself than you would ever be with someone else in your position. Notice that today. God is not adding his voice to that criticism. He sees the whole of you, including the parts you would rather nobody looked at, and he is not put off by any of it.', 'God''s love'),
('Not every day needs to be productive to be worth something. If today was slow, or you did less than you meant to, that does not make it wasted. You are not measured by output. Rest is part of how you were made to work, and taking it is obedience rather than laziness. Let today be enough as it was.', 'Rest when feeling tired'),
('Fear grows in the dark and shrinks when you say it out loud. Whatever is worrying you, name it plainly, either to God or to one person you trust. Most fears lose some of their size the moment they are spoken. The situation may not change tonight, but you do not have to carry it silently while it does.', 'Courage when facing fear'),
('Waiting is uncomfortable because nothing appears to be happening. It rarely feels like faith while you are in it. But time spent trusting God without proof is exactly what trust means, and it counts even when it feels like nothing at all. You have not been forgotten, and you are not behind.', 'Hope while waiting'),
('Something you did or said is still bothering you. Apologise if you can, put it right if it is possible, and then let it go. Turning it over again tonight will not improve it. God has already dealt with it, and continuing to punish yourself for something forgiven does not honour him. Let today be the end of it.', 'Forgiveness and grace'),
('Strength is not a feeling. Most of the time it looks like doing the ordinary next thing while still tired. You do not need to feel capable in order to be capable. God gives what the day requires, usually just enough and rarely in advance. Look at what is in front of you rather than the whole week at once.', 'Strength during difficult times'),
('Decisions are hard when you cannot see how they end. You are not failing because the way ahead is unclear. Ask God, get advice from someone who knows you well, then choose with what you have. He can work with a decision made honestly, even one that turns out differently from how you hoped it might.', 'Wisdom and guidance'),
('Notice one thing today that went right. Not a big thing. A conversation that was easier than expected, a moment of quiet, food you did not have to worry about. Naming it does not cancel out what is hard. It just stops the hard thing being the only thing you can see, and that shift matters more than it sounds.', 'Gratitude'),
('Progress is rarely a straight line. You have a good stretch and then a setback, and it feels like starting over. It is not. Something that dips is still moving. Measure across months rather than days, and be as patient with yourself as you would be with anyone else making the same slow progress.', 'Patience'),
('Someone is going to have an easier day because of something small you do. A message sent, a bit of patience held onto, a job done without being asked. None of it will be noticed and it still counts. God sees the things nobody thanks you for, and those are usually what faithfulness actually looks like.', 'Purpose and faith'),
('If you have been holding it together in front of everyone, you are allowed to stop for a moment. Being honest about struggling is not weakness and it will not disappoint God. He already knows. Letting one person see the real version of how you are doing is usually where things start getting lighter.', 'Healing and comfort'),
('You have kept going at something for a long time with very little to show for it. That is exhausting and nobody has said thank you. Rest properly, then decide again tomorrow. Not because stopping would be wrong, but because it may be worth more than it currently looks from where you are standing.', 'Perseverance after disappointment'),
('You do not need the whole plan before you take the next step. Most people only ever get enough light for the bit of road immediately ahead. If that is where you are, you are not doing it wrong. Take the next honest step and trust God with the part you genuinely cannot work out yet.', 'Trusting God''s direction'),
('There is a difference between being busy and being weighed down. Busy passes when the week ends. Weighed down follows you into the evening. If that is you, work out what you are actually carrying, because it is rarely only the schedule. Bring the real thing to God and let someone take a piece of it.', 'Rest when feeling tired'),
('God is not distant today and he is not disappointed in you. Those two ideas cause more damage than almost anything else people believe about him. He is close, he is patient, and he is glad you are here. You do not have to earn that, or feel it strongly, for it to be true.', 'God''s love'),
('Something did not go the way you hoped and you are still adjusting to it. Disappointment deserves a bit of time rather than being argued away. Sit with it honestly. God is not asking you to pretend you are fine. He is asking you to trust him with the version of the future you did not choose.', 'Perseverance after disappointment'),
('Peace does not mean the situation resolved. It means you are not facing it alone, which is a different thing and often a better one. You may still be worried tonight and still be held. Try to stop measuring your faith by how calm you feel, because that was never the right measure of it.', 'Peace during stressful moments'),
('Be careful what you say about people today, especially the ones who are difficult. You do not have to feel warm towards someone to speak about them fairly. Start with not repeating the story, and notice how much easier the next conversation with them becomes. Grace usually begins somewhere that small.', 'Forgiveness and grace'),
('If you are tired in a way that sleep does not fix, that is worth paying attention to. It usually means something needs to change rather than that you need to try harder. Ask God for honesty about what it is, then tell someone, because that kind of tiredness rarely lifts while you carry it alone.', 'Rest when feeling tired'),
('You are not as far behind as you think. Comparison makes everyone else look further along, because you only see the finished parts of their lives and all of your own working out. God is not running you against anyone. Look at where you were a year ago rather than at where somebody else is now.', 'Hope while waiting'),
('Courage is usually small and unglamorous. Sending the message. Asking the question. Turning up somewhere you would rather avoid. Nobody applauds any of it and it still costs something. God is with you in the small brave things just as much as in the large ones, and today probably only asks for one.', 'Courage when facing fear'),
('Whatever is unresolved tonight will still be unresolved in the morning, and you will be better equipped to face it having slept. Worrying is not the same as preparing, though it convincingly feels like it at two in the morning. Put it down for now. God does not need you awake to keep working on it.', 'Peace during stressful moments'),
('You have more to be thankful for than you can hold in mind at once, and most of it is so ordinary that you stopped noticing years ago. Water that runs. A door that locks. Somebody who would answer if you called them. None of that is guaranteed to anyone, and today it was given to you again.', 'Gratitude');

-- ---------- 20260912_general_reminders.sql ----------
-- Reminders become general, and every verse in the Bible becomes available.
--
-- WHY THIS CHANGES THE ARITHMETIC
--
-- Reminders used to belong to a verse, so the supply of daily content was the
-- number of reminders, and each one was spent for good. That capped the whole
-- feature at a few dozen days.
--
-- A general reminder can sit under any verse. The unit of content is therefore
-- the pairing, not the reminder, and the supply is verses multiplied by
-- reminders. With the whole Bible imported that is 31,102 verses against a few
-- hundred reminders, which is millions of distinct pairings without writing
-- millions of anything.
--
-- WHAT IS STILL GUARANTEED
--
--   A pairing is used once, ever.          unique (verse_id, reminder_id)
--   Nobody reads the same reminder twice.  unique (user_id, reminder_id)
--   No two people share a verse in a day.  unique (assigned_on, verse_id)
--   One assignment per person per day.     unique (user_id, assigned_on)
--
-- The first of those is what you asked for: a verse never carries the same
-- reminder a second time. The second keeps it feeling personal, because no
-- individual ever sees a repeat even though the pool is shared.

-- Reminders no longer belong to a verse.
alter table public.daily_reminders drop column if exists verse_id;

-- A verse needs a flag for whether it works as a daily reading. Genealogies,
-- census lists and legal codes are scripture, but opening the site to a list of
-- names is not what this feature is for. Everything is imported; this decides
-- what the daily draw can pick.
alter table public.daily_verses
  add column if not exists devotional boolean not null default true;

comment on column public.daily_verses.devotional is
  'Eligible for the daily draw. Cleared for verse lists, genealogies and fragments.';

create index if not exists daily_verses_devotional_idx
  on public.daily_verses (devotional) where status = 'active';

-- Rebuild the assignment constraints around the pairing.
alter table public.daily_assignments drop constraint if exists reminder_used_once;
alter table public.daily_assignments drop constraint if exists pairing_used_once;
alter table public.daily_assignments drop constraint if exists reminder_seen_once_per_user;

alter table public.daily_assignments
  add constraint pairing_used_once unique (verse_id, reminder_id);

alter table public.daily_assignments
  add constraint reminder_seen_once_per_user unique (user_id, reminder_id);

-- ---------- 20260912_generate_whole.sql ----------
-- Generation without concatenation.
--
-- A template is a finished reminder now, so generating one is choosing a
-- template that has not been used for this verse and storing it. Nothing is
-- joined to anything, which is what guarantees the grammar holds: the text a
-- reader sees is the text somebody wrote and checked.
--
-- The pool is templates multiplied by verses. Thirty templates against 13,239
-- eligible verses is just under 400,000 reminders today, and each template
-- added is another 13,239.

drop function if exists public.generate_reminder_for(uuid);

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  t      record;
  new_id uuid;
  tries  int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 6;

    -- A template not yet used for this verse. Every verse can therefore carry
    -- every template exactly once, and never the same words twice.
    select rt.id, rt.text, rt.focus_tag into t
    from public.reminder_templates rt
    where rt.status = 'active'
      and rt.text is not null
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every template has been used for this verse. The caller moves to another
    -- verse rather than repeating one.
    if not found then
      return null;
    end if;

    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, t.text, t.focus_tag, t.focus_tag, t.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        -- Another request stored this template for this verse first, or the
        -- similarity guard caught it. Try a different template.
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;

-- The closings existed only to pad a concatenated reminder to length. Nothing
-- composes any more, so they are gone rather than left to confuse the next
-- person reading this schema.
drop table if exists public.reminder_closings;

-- ---------- 20260912_generated_reminders.sql ----------
-- Machine-written reminders, held for review.
--
-- Generated text is not shown to anybody until a leader approves it. This is
-- commentary on Scripture published under the church's name, so there is a
-- person between the model and the congregation. The hand-written library needs
-- no such gate because a person already wrote it.
--
-- Nothing here depends on a key being present. With no key configured the
-- generator simply never runs, the library keeps serving, and the site behaves
-- exactly as it does today.

-- 'pending' joins the existing states. Only 'active' is ever drawn.
alter table public.daily_reminders drop constraint if exists daily_reminders_status_check;
alter table public.daily_reminders
  add constraint daily_reminders_status_check
  check (status in ('active', 'pending', 'rejected', 'retired'));

alter table public.daily_reminders
  add column if not exists source       text not null default 'library'
    check (source in ('library', 'generated')),
  add column if not exists reviewed_by  uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at  timestamptz,
  add column if not exists model        text;

comment on column public.daily_reminders.source is
  'library: written by a person. generated: written by a model and reviewed before use.';

create index if not exists daily_reminders_pending_idx
  on public.daily_reminders (created_at) where status = 'pending';

-- Staff read the queue and decide. Members never see a pending reminder,
-- because the claim function only ever selects status = 'active'.
alter table public.daily_reminders enable row level security;

drop policy if exists "staff review reminders" on public.daily_reminders;
create policy "staff review reminders"
  on public.daily_reminders for select
  using (is_staff());

drop policy if exists "staff decide reminders" on public.daily_reminders;
create policy "staff decide reminders"
  on public.daily_reminders for update
  using (is_staff()) with check (is_staff());

grant select, update on public.daily_reminders to authenticated;

-- How much unreviewed work is waiting, and how much approved content is left.
create or replace function public.reminder_queue_stats()
returns table (pending bigint, approved bigint, rejected bigint, verses_covered bigint)
language sql
security definer
set search_path = public
stable
as $$
  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'active'),
    count(*) filter (where status = 'rejected'),
    count(distinct verse_id) filter (where status = 'active')
  from public.daily_reminders;
$$;

revoke all on function public.reminder_queue_stats() from public;
grant execute on function public.reminder_queue_stats() to authenticated;

-- ---------- 20260912_generation_compose_pairs.sql ----------
-- Compose a reminder from two templates and a closing line about the verse.
--
-- The first attempt used one template per reminder, and 48 of the 50 composed
-- to fewer than 50 words. The length constraint rejected them, the generator
-- caught the exception and returned null, and no reminder was ever produced.
-- Failing silently is the worst version of that, so the length is now met by
-- construction rather than by hoping the wording is long enough.
--
-- Composing a pair also fixes the capacity question properly. Fifty templates
-- taken two at a time is 2,450 ordered pairs, multiplied again by the closing
-- lines and by every verse in the Bible. That is tens of millions of distinct
-- reminders without writing tens of millions of anything.

create table if not exists public.reminder_closings (
  id     uuid primary key default gen_random_uuid(),
  line   text not null unique,
  status text not null default 'active' check (status in ('active', 'retired')),
  constraint closing_no_em_dash check (line !~ '[—–]')
);

-- These are the only part of a reminder that points at the verse directly,
-- which is what ties the reflection to the Scripture above it.
insert into public.reminder_closings (line) values
  ('Sit with the verse above for a moment before the day takes over.'),
  ('Read it once more slowly, and let it be the last word rather than the first worry.'),
  ('Carry that verse with you today rather than the running commentary in your head.'),
  ('Come back to those words later, when the day has had a chance to argue with them.'),
  ('Let the verse above stand, even on a day when you cannot feel that it is true.'),
  ('Take that line into whatever you are walking into next.'),
  ('If nothing else lands today, let the verse above be the thing that does.'),
  ('Say it back to yourself tonight, quietly, and see what settles.')
on conflict (line) do nothing;

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  a        record;
  b        record;
  closing  text;
  composed text;
  new_id   uuid;
  tries    int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 8;

    -- The lead template, not yet used for this verse.
    select * into a
    from public.reminder_templates rt
    where rt.status = 'active'
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every lead template has been used for this verse. The caller moves on to
    -- a different verse rather than repeating one.
    if not found then
      return null;
    end if;

    -- A second template supplies the middle thought, and must be a different
    -- one so the sentence does not repeat itself.
    select * into b
    from public.reminder_templates rt
    where rt.status = 'active' and rt.id <> a.id
    order by random()
    limit 1;

    select line into closing
    from public.reminder_closings
    where status = 'active'
    order by random()
    limit 1;

    composed := a.opening || ' ' || a.body || ' ' || b.body || ' ' || a.closing || ' ' || closing;

    -- The table constraints are the validator: word count, no em dash, no
    -- emoji, no hashtag, plus the similarity trigger scoped to this verse. A
    -- rejected candidate simply means trying a different pair.
    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, composed, a.focus_tag, a.focus_tag, a.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;

-- The composed length is now a property of the data, so it is worth asserting
-- rather than assuming. A pair plus a closing sits comfortably inside 50 to 90.
do $$
declare too_short int;
begin
  select count(*) into too_short
  from (
    select array_length(regexp_split_to_array(
      trim(a.opening || ' ' || a.body || ' ' || b.body || ' ' || a.closing || ' ' || c.line),
      '\s+'), 1) w
    from public.reminder_templates a
    cross join lateral (select body from public.reminder_templates where id <> a.id limit 3) b
    cross join lateral (select line from public.reminder_closings limit 2) c
  ) x
  where w < 50 or w > 90;

  if too_short > 0 then
    raise notice 'compositions outside 50 to 90 words: %', too_short;
  end if;
end $$;

-- ---------- 20260912_passages.sql ----------
-- Show a passage, not a stranded verse.
--
-- Verse divisions were added centuries after the text was written and they cut
-- across sentences constantly. Isaiah 38:2 ends on a comma; on its own it reads
-- as a fragment. Drawing a single verse was giving people half a thought.
--
-- HOW THE BOUNDARIES ARE FOUND
--
-- A passage is a run of verses inside one chapter that begins after a sentence
-- ends and finishes where one ends. From the drawn verse it walks backwards
-- while the preceding verse does not close a sentence, then forwards until one
-- closes, then keeps going to a minimum length so there is some context rather
-- than a lone line, always stopping on a sentence end.
--
-- It is a heuristic over punctuation rather than real paragraph data, because
-- the imported text has no paragraph markers. It gets the common cases right
-- and errs towards including a little more, which is the safer direction.

-- The World English Bible uses curly quotation marks, so a sentence can end
-- with a full stop followed by one or two closing quotes.
create or replace function public.ends_sentence(t text)
returns boolean
language sql
immutable
as $$
  select trim(coalesce(t, '')) ~ '[.!?]["''’”]{0,2}$';
$$;

create or replace function public.passage_for(p_verse uuid)
returns table (reference text, passage_text text, first_verse smallint, last_verse smallint)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  anchor    record;
  first_v   smallint;
  last_v    smallint;
  max_v     smallint;
  guard     int := 0;
  prev_text text;
  last_text text;
  body      text;
  words     int;
begin
  select v.book, v.chapter, v.verse, v.verse_text
    into anchor
  from public.daily_verses v where v.id = p_verse;

  if not found then
    return;
  end if;

  select max(v.verse) into max_v
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter;

  first_v := anchor.verse;
  last_v  := anchor.verse;

  -- Backwards: if the verse before this one does not close a sentence, this
  -- verse is a continuation and the thought started earlier.
  loop
    guard := guard + 1;
    exit when guard > 6 or first_v <= 1;

    select v.verse_text into prev_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = first_v - 1;

    exit when prev_text is null or public.ends_sentence(prev_text);
    first_v := first_v - 1;
  end loop;

  -- Forwards: keep going until a verse closes a sentence, then keep going a
  -- little further so the passage has some shape rather than stopping at the
  -- first full stop.
  guard := 0;
  loop
    guard := guard + 1;
    exit when guard > 8 or last_v >= max_v;

    select v.verse_text into last_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = last_v;

    select coalesce(sum(array_length(regexp_split_to_array(trim(v.verse_text), '\s+'), 1)), 0)
      into words
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter
      and v.verse between first_v and last_v;

    -- Long enough and ending cleanly: stop here.
    exit when public.ends_sentence(last_text)
          and (last_v - first_v + 1) >= 3
          and words >= 45;

    -- Never run away with it, even mid-sentence.
    exit when words > 170 or (last_v - first_v + 1) >= 8;

    last_v := last_v + 1;
  end loop;

  select string_agg(v.verse_text, ' ' order by v.verse)
    into body
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter
    and v.verse between first_v and last_v;

  return query select
    anchor.book || ' ' || anchor.chapter || ':' || first_v
      || case when last_v > first_v then '-' || last_v else '' end,
    body,
    first_v,
    last_v;
end;
$$;

revoke all on function public.passage_for(uuid) from public;
grant execute on function public.passage_for(uuid) to authenticated, anon;

-- The daily draw returns the passage rather than the single verse it landed on.
-- The verse still decides what is drawn; the passage is how it is shown.
create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 20;

      if is_member then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random() limit 1;

        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1 from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random() limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1 from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random() limit 1;
        end if;
      end if;

      exit when v_id is null;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, p_day, 'verse')
      on conflict do nothing
      returning id into made;

      if made is null then
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, p.reference, p.passage_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  cross join lateral public.passage_for(a.verse_id) p
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

-- ---------- 20260912_reminder_generation.sql ----------
-- Generating reminders per verse, and scoping duplicate checks to the verse.
--
-- WHY UNIQUENESS MOVES FROM GLOBAL TO PER VERSE
--
-- A reminder belongs to one verse now. A template composed under Psalm 23 and
-- the same template composed under Romans 8 are different reminders, because
-- the verse they sit beneath is what gives them their meaning. A global
-- uniqueness rule would let each template be used exactly once in the entire
-- Bible, which caps the pool at the number of templates.
--
-- Scoped to the verse, 50 templates against roughly 15,000 devotional verses is
-- about 750,000 reminders, and adding templates multiplies that rather than
-- adding to it. Duplicate protection is not weakened: within any one verse, no
-- two reminders may be identical or near identical, which is the comparison
-- that actually matters to a reader.

drop index if exists daily_reminders_norm_uniq;
create unique index if not exists daily_reminders_verse_norm_uniq
  on public.daily_reminders (verse_id, reminder_norm);

-- The near-duplicate guard, now comparing within the verse. It still reads
-- new.reminder directly rather than the generated column, because a stored
-- generated column is not populated until after a before-insert trigger runs.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  candidate_norm text;
  clash record;
begin
  candidate_norm := trim(regexp_replace(
    regexp_replace(lower(new.reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));

  select id, similarity(reminder_norm, candidate_norm) as score
    into clash
  from public.daily_reminders
  where id <> new.id
    and verse_id = new.verse_id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to an existing reminder for this verse (%)',
      round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Generation
--
-- WHEN IT RUNS: during assignment, on demand, for one verse at a time. Not in a
-- background job, because the pool is enormous and pre-generating it would mean
-- writing three quarters of a million rows nobody may ever read. Not before
-- assignment either, because which verse a reader gets is not known until then.
--
-- The generator makes at most one reminder per call and the claim loop is
-- bounded, so a single request can never trigger unbounded generation.
-- ---------------------------------------------------------------------------

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  t          record;
  composed   text;
  new_id     uuid;
  tries      int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 5;

    -- A template not yet used for this verse.
    select * into t
    from public.reminder_templates rt
    where rt.status = 'active'
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every template already used for this verse.
    if not found then
      return null;
    end if;

    composed := t.opening || ' ' || t.body || ' ' || t.closing;

    -- The constraints on daily_reminders do the validating: word count, no em
    -- dash, no emoji, no hashtag, and the similarity trigger above. A candidate
    -- that fails any of them raises, and the loop tries another template rather
    -- than storing something invalid.
    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, composed, t.focus_tag, t.focus_tag, t.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
    -- Lost a race, or the candidate was rejected. Try a different template.
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;

-- ---------- 20260912_reminder_library_a.sql ----------
-- Reminder library, part one.
--
-- Each row is a finished reminder between 50 and 90 words. Written to be read
-- aloud without stumbling: short sentences, ordinary words, no church jargon
-- and no assumption about who is reading. Nothing here guesses whether you have
-- children, a job, or a diagnosis.

insert into public.reminder_templates (text, focus_tag, tone) values

('There is something you have been carrying around for a while, and it has not sorted itself out. You can bring it to God exactly as it is. You do not need to tidy it up first or find better words for it. Saying honestly that something is hard is not a failure of faith. It is how you stop carrying it on your own.',
 'Honesty with God', 'gentle'),

('You are probably harder on yourself than you would ever be with a friend in the same situation. Notice that today. God is not joining in with that voice. He sees all of you, including the parts you would rather nobody saw, and he has not walked away. Try speaking to yourself the way he speaks to you.',
 'God''s love', 'gentle'),

('Not every day has to be productive to be worth something. If today was slow, or you got less done than you meant to, that does not make it a wasted day. You were never measured by how much you produced. Rest is part of how you were made, and taking it is not laziness. Let today be enough as it was.',
 'Rest', 'gentle'),

('Fear gets bigger in the dark and smaller when you say it out loud. Whatever is worrying you, name it plainly, either to God or to somebody you trust. Most fears lose some of their size the moment they are spoken. The situation might not change tonight, but you will not be carrying it silently while it does.',
 'Courage', 'steady'),

('Waiting is hard because nothing looks like it is happening. It rarely feels like faith while you are in the middle of it. But trusting God when you cannot see any proof is exactly what trust means, and it still counts on the days it feels like nothing at all. You have not been forgotten and you are not running late.',
 'Waiting', 'steady'),

('Something you said or did is still bothering you. Put it right if you can, apologise if you should, and then let it go. Going over it again tonight will not make it better. God has already dealt with it, and punishing yourself for something he has forgiven does not help anybody. Let today be where it ends.',
 'Forgiveness', 'steady'),

('Strength is not a feeling. Most days it looks like getting on with the next ordinary thing while still tired. You do not have to feel capable in order to be capable. God gives you what today needs, usually just enough and rarely early. Look at what is actually in front of you instead of the whole week at once.',
 'Strength', 'steady'),

('Decisions are hard when you cannot see how they turn out. You are not failing just because the way ahead is unclear. Ask God, talk it over with somebody who knows you well, then choose with what you have. He can work with a decision made honestly, even one that turns out differently from how you hoped.',
 'Guidance', 'steady'),

('Try to notice one thing today that went right. It does not have to be big. A conversation that was easier than expected. Ten minutes of quiet. A meal you did not have to worry about. Naming it does not cancel out what is hard. It just stops the hard thing being the only thing you can see.',
 'Gratitude', 'gentle'),

('Getting better at anything is rarely a straight line. You have a good stretch, then a setback, and it feels like starting again from the beginning. It is not. Something that dips is still moving. Look at where you are over months rather than days, and be as patient with yourself as you would be with anyone else.',
 'Patience', 'steady'),

('Somebody will have an easier day because of something small you do. A message you send. A bit of patience you hold on to. A job you do without being asked. None of it will get noticed and it still matters. God sees the things nobody thanks you for, and those are usually the ones that hold everything together.',
 'Purpose', 'steady'),

('If you have been holding it together in front of everyone, you are allowed to stop for a minute. Admitting you are struggling is not weakness, and it will not disappoint God. He already knows. Letting one person see how you are really doing is usually where things start to get lighter.',
 'Honesty', 'gentle'),

('You have kept going at something for a long time without much to show for it. That is tiring, and nobody has said thank you. Rest properly first, then decide tomorrow. Not because giving up would be wrong, but because a decision made when you are worn out is rarely the one you would make after a good night.',
 'Perseverance', 'direct'),

('You do not need to see the whole plan before you take the next step. Most people only ever get enough light for the bit of road right in front of them. If that is where you are, you are not doing it wrong. Take the next honest step and leave the part you cannot work out with God.',
 'Trusting God''s direction', 'steady'),

('There is a difference between being busy and being weighed down. Busy stops when the week does. Weighed down follows you home. If that is you, work out what you are actually carrying, because it is usually more than the schedule. Bring the real thing to God, and let somebody help you with part of it.',
 'Rest', 'steady'),

('God is not far away today, and he is not disappointed in you. Those two ideas do more damage than almost anything else people believe about him. He is close, he is patient, and he is glad you are here. You do not have to earn that or even feel it for it to be true.',
 'God''s love', 'gentle'),

('Something has not turned out the way you hoped, and you are still getting used to it. Disappointment deserves a bit of time rather than being talked out of you. Sit with it honestly. God is not asking you to pretend you are fine. He is asking you to trust him with a future you did not choose.',
 'Disappointment', 'gentle'),

('Peace does not mean the problem is solved. It means you are not facing it on your own, which is a different thing and often a better one. You can still be worried tonight and still be held. Try to stop measuring your faith by how calm you feel, because that was never a fair test of it.',
 'Peace', 'steady'),

('Be careful how you talk about people today, especially the ones you find difficult. You do not have to feel warm towards somebody to speak fairly about them. Start by not repeating the story, and see how much easier the next conversation becomes. Grace nearly always starts with something that small.',
 'Grace', 'direct'),

('If you are tired in a way that sleeping does not fix, that is worth paying attention to. It usually means something needs to change rather than that you need to try harder. Ask God to show you honestly what it is. Then tell somebody, because that kind of tiredness rarely lifts while you are carrying it alone.',
 'Rest', 'direct'),

('You are not as far behind as you think. Comparing yourself to other people makes everyone else look further along, because you see their finished results and all of your own mess. God is not running you against anybody. Look at where you were a year ago rather than at where somebody else is today.',
 'Contentment', 'steady'),

('Courage is usually small and unimpressive. Sending the message. Asking the question. Turning up somewhere you would rather avoid. Nobody claps for any of it, and it still costs you something. God is with you in the small brave things just as much as the big ones, and today is probably only asking for a small one.',
 'Courage', 'steady'),

('Whatever is unresolved tonight will still be unresolved in the morning, and you will be in a much better state to face it after some sleep. Worrying is not the same as preparing, even though at two in the morning it feels like it. Put it down for now. God does not need you awake to keep working.',
 'Rest', 'gentle'),

('You have more to be grateful for than you can hold in your head at once, and most of it is so ordinary that you stopped noticing years ago. Water that runs. A door that locks. Somebody who would pick up if you rang them. None of that is guaranteed to anybody, and today you have it again.',
 'Gratitude', 'gentle'),

('When you feel like nobody has noticed you, remember that being seen by people and being known by God are not the same thing. One depends on who happens to be looking that day. The other does not change when the room is empty. You are known today, whether or not a single person says so.',
 'Being known', 'gentle'),

('If you feel like you do not belong here, that feeling is not the truth of the situation. Belonging was never something you earned by fitting in well enough or knowing the right things. It was given to you. You are already inside. You are not auditioning, and nobody is deciding whether to keep you.',
 'Belonging', 'gentle'),

('Doubt is not the opposite of faith. Almost everybody who has believed anything worth believing has been through a stretch like the one you might be in. Bring the questions with you instead of leaving them at the door. A faith that has never been asked anything difficult has not been tested yet.',
 'Doubt', 'steady'),

('Grief does not run to a timetable, and there is no point at which you are supposed to be over it. If you are carrying a loss, God is not waiting on the other side of it for you to pull yourself together. He is in it with you. You can bring him the anger as well as the sadness.',
 'Comfort', 'gentle'),

('If you have made the same mistake again, mercy is not a supply you have been slowly using up since you were young. There is genuinely more of it waiting. Get up again today, but let it be hope doing the lifting rather than shame. Shame has never once made anybody better at anything.',
 'Mercy', 'steady'),

('When something good happens unexpectedly, let it land properly instead of bracing for whatever comes next. Good things are not a trick, and enjoying one does not use up your share. You are allowed to be glad today without checking over your shoulder. Take the good thing as it is and say thank you for it.',
 'Joy', 'gentle');

-- ---------- 20260912_reminder_library_b.sql ----------
-- Reminder library, part two.
--
-- Thirty more finished reminders. Same rules as part one: 50 to 90 words, plain
-- words, correct grammar, no assumption about the reader's circumstances.
-- Written to cover situations part one did not reach, so the library spreads
-- across worry, loneliness, anger, shame, change, money, health, and the
-- ordinary middle of a week where nothing much is happening.

insert into public.reminder_templates (text, focus_tag, tone) values

('Some weeks nothing much happens. No crisis, no breakthrough, just the same round of ordinary days. Those stretches are not gaps between the real parts of your life. Most of a life is made of them, and God is as present in a quiet Tuesday as in anything dramatic. You are not waiting for your life to start.',
 'The ordinary', 'steady'),

('If your mind keeps running the same worry on a loop, that is exhaustion talking as much as anything. A tired brain is very bad at telling you the truth about how bad things are. Do one small useful thing, then stop. You can look at the whole of it again when you have slept.',
 'Worry', 'gentle'),

('Loneliness is not proof that something is wrong with you. It is information about your circumstances, not about your worth, and almost everybody feels it at some point without saying so. Reach out to one person today, even briefly and even badly. You do not have to explain yourself well to be worth talking to.',
 'Loneliness', 'gentle'),

('Anger is usually pain that has run out of patience. If you are angry today, it is worth asking quietly what is underneath it before you decide what to do. You can bring the anger to God as it is. He is not fragile, and he would rather have the honest version than a polite one.',
 'Anger', 'direct'),

('Shame and conviction are not the same thing, and it helps enormously to tell them apart. Conviction points at something you did and offers you a way to put it right. Shame points at you and offers nothing. Only one of those comes from God, and it is not the one that leaves you stuck.',
 'Shame', 'steady'),

('Change is uncomfortable even when it is good, and being unsettled by it does not mean you chose wrong. Anything new strips away the small routines that made you feel capable. That feeling passes as the routines rebuild. Give it longer than feels reasonable before you decide how it is going.',
 'Change', 'steady'),

('When money is tight, the worry follows you into every room and every conversation. God is not disappointed in you for it, and being short this month is not a verdict on your character. Tell him plainly what the gap is. Then tell one person you trust, because this particular fear gets much heavier in private.',
 'Provision', 'gentle'),

('If your body is not doing what it used to, that is a real loss and it deserves to be named as one. You are not required to be cheerful about it. God is not only available to people who feel well. He is the steady thing underneath on the days you have very little to bring.',
 'Health', 'gentle'),

('You are allowed to say no to something this week. Saying yes to everything is not generosity, it is usually fear of what people will think. The things you actually care about need room, and room only exists if something else does not get it. Choose deliberately rather than by default.',
 'Boundaries', 'direct'),

('Somebody has let you down and you are still deciding what to do about it. People will fail you, sometimes badly, and that is not evidence that God has. Let this cost you less than it wants to. You can be honest about the hurt without handing it the rest of your year.',
 'Trust', 'steady'),

('If you keep putting off a conversation, the delay is probably costing you more than the conversation would. Wait until you are calm rather than until you feel ready, because ready may never turn up. Then say the true thing kindly, and let the other person have their reaction without managing it for them.',
 'Courage', 'direct'),

('The version of you that other people see is always partial, and so is the version you see of them. Everyone is carrying something they have not mentioned. That is worth remembering both ways today: be gentler with the difficult person, and gentler with yourself for the parts nobody has noticed.',
 'Compassion', 'gentle'),

('Prayer does not require the right words or a particular posture or a good mood. If all you can manage today is a sentence in the car, that counts. God is not marking it. Being turned in his direction, even badly and even briefly, is the whole of what is being asked.',
 'Prayer', 'gentle'),

('You do not have to have a strong opinion about everything you read today. Much of what arrives on a screen is designed to make you feel urgently involved in something you cannot affect. Put some of it down. Peace is partly a matter of deciding what actually belongs to you.',
 'Peace', 'direct'),

('If you are dreading something specific this week, it is worth remembering that God is already there. Not waiting at the end of it, but in the room itself, before you arrive. You can be nervous and still go. Nerves are not a sign you are outside his will; they are a sign it matters.',
 'Courage', 'steady'),

('Being needed and being loved are not the same thing, though it is easy to confuse them when you are useful to a lot of people. If everything you do stopped tomorrow, you would still be exactly as valuable. Rest on that today rather than on how much you managed to get through.',
 'Worth', 'gentle'),

('Forgiving somebody does not mean deciding that what they did was fine. It means putting down a debt you were never going to collect anyway. That can take a long time and you may have to decide it more than once. Start from where you honestly are rather than where you think you should be.',
 'Forgiveness', 'steady'),

('Hope is not the same as optimism about how things will turn out. Optimism is a guess about circumstances. Hope is trust in the character of the one holding them. You do not have to feel hopeful to have hope, which is useful, because feelings are not reliable on a difficult week.',
 'Hope', 'steady'),

('If you have been comparing your life to what other people put online, stop for a moment and remember what you are actually looking at. Edited highlights, chosen carefully, with everything ordinary removed. Nobody lives there. Your unedited Tuesday is not losing to it.',
 'Contentment', 'direct'),

('When you have nothing left to give, that is not a failure of faith or of character. Everybody runs out. God is not only interested in you when you are useful. Turning up empty is still turning up, and there is no minimum you have to bring before you are welcome.',
 'Grace', 'gentle'),

('There is somebody you have been meaning to thank and have not got round to. Do it today, briefly, without making it a big occasion. Gratitude said out loud does something that gratitude felt privately does not, both for them and for you. It will take two minutes.',
 'Gratitude', 'direct'),

('If a decision has been sitting on you for weeks, notice that not deciding is also a decision, and usually a worse one. You will rarely have all the information you want. Ask God, take advice, and then choose. A decision made honestly can be worked with, even if it turns out imperfectly.',
 'Guidance', 'direct'),

('You are not responsible for how everybody else feels. Caring about people is right, and carrying their reactions as though you caused them is something else, and it will wear you down. Do the loving thing and then let go of the outcome. That part was never yours to manage.',
 'Boundaries', 'steady'),

('Some prayers are answered slowly enough that you only notice years later. That does not mean nothing happened at the time. If you are still waiting on something you asked for long ago, you have not been ignored. Keep asking, and keep living in the meantime rather than holding your breath.',
 'Waiting', 'steady'),

('When you cannot feel anything much, faith is not gone. Feelings come and go with sleep and light and how the week has treated you. What you believe does not run on them. Keep doing the ordinary things you would do anyway, and let the feeling come back in its own time.',
 'Faith', 'steady'),

('If you feel like you are pretending to be more together than you are, almost everybody around you feels the same. The pretending is exhausting and it keeps people at a distance you did not intend. Let one person see the real version this week and notice how much lighter it gets.',
 'Honesty', 'gentle'),

('Rest is not the reward you get after everything is finished, because it will never all be finished. It is part of the work, built into how the week is meant to run. Take some today rather than saving it for a quieter time that is not coming on its own.',
 'Rest', 'direct'),

('You have survived every difficult day so far, including the ones you were sure you would not manage. That is not luck and it is not only your own strength. Look back at one of them today and let it change how you look at the thing in front of you now.',
 'Perseverance', 'steady'),

('When you are surrounded by people and still feel alone, that is one of the strangest kinds of loneliness and one of the most common. It usually means the conversations have stayed shallow rather than that nobody cares. Say one true thing to somebody today and see what happens.',
 'Loneliness', 'gentle'),

('If today went well, let that be enough without immediately turning it into pressure to repeat it. A good day is a gift rather than a new standard you now have to meet. Say thank you for it, sleep properly, and let tomorrow be its own thing.',
 'Joy', 'gentle');

-- ---------- 20260912_reminder_library_c.sql ----------
-- Reminder library, part three.
--
-- Length is not a rule any more, so these run as long or as short as the
-- thought needs. Some are three sentences. A few are one. The only rules left
-- are the ones about writing well: plain words, correct grammar, no assumption
-- about who is reading, and nothing that promises an outcome God has not.

insert into public.reminder_templates (text, focus_tag, tone) values

('You are allowed to not be fine today. Nobody is asking you to perform.',
 'Honesty', 'gentle'),

('Whatever you got wrong yesterday, it is not following you into today. God is not keeping a running total, and neither should you. Start again.',
 'Grace', 'gentle'),

('If you are waiting for the moment when you feel ready, it may not arrive. Most of the important things get done by people who felt unqualified and went ahead anyway.',
 'Courage', 'direct'),

('The small kindness you are considering is worth doing. It will cost you almost nothing and it might be the best thing that happens to somebody today.',
 'Kindness', 'gentle'),

('Being tired is not a sign that you are doing it wrong. Sometimes it just means you have been going for a long time and you need to stop for a bit.',
 'Rest', 'gentle'),

('There is nothing you can do today that would make God love you more, and nothing you have done that makes him love you less. That is not a slogan. It is the actual arrangement.',
 'God''s love', 'steady'),

('If you cannot sleep for worrying, that is worth saying out loud to God rather than lying there rehearsing it. He is awake anyway.',
 'Worry', 'gentle'),

('Do the next right thing. Not the whole plan, not the version where you have it all worked out. Just the next one.',
 'Guidance', 'direct'),

('Somebody in your life is having a much harder week than they have let on. Ask properly today, and then wait long enough for the real answer.',
 'Compassion', 'direct'),

('You will not always feel close to God, and that is normal rather than a warning sign. Closeness is not a mood. Keep turning up and it comes back.',
 'Faith', 'steady'),

('If you are afraid of getting it wrong, remember that God has worked with far worse than a genuine mistake made honestly.',
 'Courage', 'steady'),

('Take a proper break today. Not scrolling, which is not rest and never has been. Something that actually puts something back.',
 'Rest', 'direct'),

('The thing you keep apologising for is probably not as big as it feels from the inside. Say sorry once, mean it, and then stop.',
 'Forgiveness', 'direct'),

('You have been given today, which is not nothing. Whatever else is uncertain, that much arrived.',
 'Gratitude', 'gentle'),

('Trying and failing is not the same as failing to try, and God can see the difference even when nobody else can.',
 'Perseverance', 'steady'),

('If everything feels like too much, narrow it down. What needs doing in the next hour? Do that, and let the rest wait its turn.',
 'Overwhelm', 'direct'),

('Being misunderstood is painful, and it does not change what is true about you. God is not working from other people''s version.',
 'Identity', 'steady'),

('Hope is not a feeling you have to work up. It is a decision about who is holding the future, and you can make it on a bad day.',
 'Hope', 'steady'),

('Somebody prayed for you before you were old enough to know it. That has not stopped.',
 'Belonging', 'gentle'),

('If you are carrying something you have never said out loud, today would be a good day to tell one person. It gets lighter the moment it stops being a secret.',
 'Honesty', 'direct'),

('You do not have to fix everybody. Being present is usually more use than being useful.',
 'Compassion', 'gentle'),

('The prayer you keep repeating is not being ignored just because nothing has changed yet. Keep asking.',
 'Waiting', 'steady'),

('There is grace for today. Not stockpiled for the whole year ahead, and not left over from last week. Today.',
 'Grace', 'steady'),

('If you have drifted, coming back is much simpler than you are imagining. There is no process. You just come back.',
 'Return', 'gentle'),

('Notice what you already have before you think about what is missing. Both are true, but only one of them is in front of you.',
 'Gratitude', 'steady'),

('You are not behind. That feeling comes from comparing your ordinary Tuesday with everybody else''s highlights.',
 'Contentment', 'direct'),

('Peace is not the absence of trouble. It is knowing you are not on your own in it.',
 'Peace', 'steady'),

('Whatever you are dreading this week, God is already there and has been for a while.',
 'Courage', 'gentle'),

('Say thank you to somebody today who will not expect it. It takes ten seconds and they will remember it much longer than that.',
 'Gratitude', 'direct'),

('You are loved right now, in the state you are actually in rather than the improved version you keep planning. That is the whole point of it.',
 'God''s love', 'gentle');

-- ---------- 20260912_templates_and_topic_seed.sql ----------
-- Reminder templates, and the curated verse list visitors may see.

-- ---------------------------------------------------------------------------
-- Templates
--
-- A template is an opening move and a shape, not a sentence with a hole in it.
-- The generator composes a template with the verse to produce a reminder, and
-- the composed text is then checked for duplicates before it is stored. Shallow
-- templates that merely restate the verse are deliberately avoided.
-- ---------------------------------------------------------------------------

create table if not exists public.reminder_templates (
  id         uuid primary key default gen_random_uuid(),
  opening    text not null,
  body       text not null,
  closing    text not null,
  focus_tag  text not null,
  tone       text not null default 'steady' check (tone in ('steady', 'gentle', 'direct')),
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  -- Role-specific language is rejected at the door rather than in review. If a
  -- template assumes the reader is a parent or an employee, the assumption is
  -- wrong for most readers and the message stops landing.
  constraint template_no_roles check (
    (opening || ' ' || body || ' ' || closing) !~*
    '\m(parent|parents|mother|father|mum|dad|student|students|employee|employees|husband|wife|spouse|teenager|child of yours|your kids|your children|your job|your boss)\M'
  ),
  constraint template_no_em_dash check ((opening || body || closing) !~ '[—–]'),
  constraint template_no_emoji   check ((opening || body || closing) ~ '^[\x00-\x7F''’"“”]*$')
);

create unique index if not exists reminder_templates_uniq
  on public.reminder_templates (md5(lower(opening || body || closing)));

alter table public.daily_reminders
  drop constraint if exists daily_reminders_template_fk;
alter table public.daily_reminders
  add constraint daily_reminders_template_fk
  foreign key (template_id) references public.reminder_templates(id) on delete set null;

insert into public.reminder_templates (opening, body, closing, focus_tag, tone) values
('When you feel unseen,', 'it is worth remembering that being noticed by people and being known by God are not the same thing. One depends on who happens to be looking. The other does not change on a quiet day.', 'You are known today whether or not anyone says so.', 'Being known', 'gentle'),
('In seasons of waiting,', 'the absence of visible progress is not the absence of God working. Waiting rarely feels like faith while you are inside it, and it counts anyway.', 'You have not been forgotten, and you are not behind.', 'Hope while waiting', 'steady'),
('If you are carrying something heavy,', 'you do not have to find the right words for it before you bring it to God. Honesty about what is hard is not a failure of faith. It is the start of putting it down.', 'Say it plainly today, however unfinished it sounds.', 'Peace under pressure', 'gentle'),
('When life feels heavy,', 'the instruction is rarely to push harder. Rest is part of how you were made to work, and taking it is obedience rather than laziness.', 'Let today be enough as it actually was.', 'Rest', 'gentle'),
('When things are better than expected,', 'notice it out loud rather than waiting for the next problem. Gratitude is not a denial of what is hard. It stops the hard thing being the only thing in view.', 'Name one good thing before the day closes.', 'Gratitude', 'steady'),
('If you do not know what to do next,', 'you are not failing because the way ahead is unclear. Most people only ever get enough light for the part of the road immediately in front of them.', 'Take the next honest step and leave the rest with God.', 'Trusting God''s direction', 'steady'),
('When you are tempted to give up,', 'rest properly first and decide afterwards. Exhaustion is a poor advisor, and a decision made at the end of a long stretch is rarely the one you would make rested.', 'Decide tomorrow, not tonight.', 'Perseverance', 'direct'),
('When fear arrives,', 'say the thing out loud, either to God or to one person you trust. Most fears lose some of their size the moment they are spoken and stop being carried alone.', 'The situation may not change tonight. You still do not face it by yourself.', 'Courage', 'steady'),
('If you are being hard on yourself,', 'notice that you would not speak this way to anyone else in your position. God is not adding his voice to that criticism.', 'Try hearing yourself the way he hears you.', 'God''s love', 'gentle'),
('When something did not go as you hoped,', 'disappointment deserves a little time rather than being argued away. Sitting with it honestly is not a lack of trust.', 'You are allowed to grieve the version of the future you did not choose.', 'Disappointment', 'gentle'),
('When you feel far from God,', 'distance is usually felt rather than actual. Feelings are real information about you and poor information about where he is.', 'He has not moved, even on the days you cannot tell.', 'God''s nearness', 'steady'),
('If today felt wasted,', 'output is not the measure. A slow day is not a failed one, and you were never valued by how much you produced.', 'Today counted, whether or not it looked like it.', 'Worth', 'gentle'),
('When you are worn out,', 'the tiredness that sleep does not fix usually means something needs to change rather than that you need to try harder.', 'Ask for honesty about what it is, then tell somebody.', 'Rest', 'direct'),
('When regret keeps circling,', 'turning it over again tonight will not improve it. Put right what can be put right, then let it be finished.', 'What God has dealt with does not need you to keep punishing it.', 'Forgiveness', 'steady'),
('When you compare yourself to others,', 'remember you are seeing their finished parts and all of your own working out. That comparison was never fair to you.', 'Measure against where you were, not against where they are.', 'Contentment', 'steady'),
('If you are the one everybody leans on,', 'being capable is not the same as being fine. Needing help does not disqualify you from giving it.', 'Ask somebody for something this week.', 'Honesty', 'direct'),
('When the day ahead looks like too much,', 'you are not asked to carry the whole week at once. Strength tends to arrive as enough for today and rarely in advance.', 'Look only at what is actually in front of you.', 'Strength', 'steady'),
('When you cannot pray properly,', 'God is not waiting for eloquence. Being present and still breathing is a real form of holding on.', 'Silence in his direction still counts.', 'Prayer', 'gentle'),
('When you feel like you do not belong,', 'belonging here was never something you earned by fitting in well enough. It was given.', 'You are already inside, not auditioning.', 'Belonging', 'gentle'),
('If you are anxious about what you cannot control,', 'most of what you are turning over is not yours to carry, and some of it will not happen.', 'Hand it over for the night and pick up only what is yours tomorrow.', 'Peace under pressure', 'steady'),
('When somebody has hurt you,', 'forgiving does not mean deciding that what happened was acceptable. It means stopping carrying a debt that costs you more than it costs them.', 'Start where you actually are, not where you think you should be.', 'Forgiveness', 'steady'),
('When you are grieving,', 'there is no point at which you are meant to be over it, and no schedule you are behind on.', 'God is not waiting on the far side of this. He is in it with you.', 'Comfort', 'gentle'),
('When doubt turns up,', 'questions are not the opposite of faith. Most people who have believed anything worth believing went through this.', 'Bring the doubt with you rather than leaving it at the door.', 'Doubt', 'steady'),
('When you have been faithful with no result,', 'work that looks like nothing for a long time often turns out to have mattered enormously.', 'Do not judge the harvest by what you can see today.', 'Perseverance', 'steady'),
('When you feel small,', 'scale is not how God decides what matters. The things nobody thanks you for are usually the ones that hold everything together.', 'What you did today was seen.', 'Worth', 'gentle'),
('If you are dreading something,', 'he is already in the room you are dreading, and he got there before you did.', 'You are walking in, not walking in alone.', 'Courage', 'steady'),
('When you are lonely,', 'loneliness is not evidence that you are unwanted. It is information about your circumstances, not about your value.', 'Reach out once today, even briefly.', 'Loneliness', 'gentle'),
('When you have made the same mistake again,', 'mercy is not a supply you have been drawing down since childhood. There is genuinely more waiting.', 'Get up again, without shame doing the driving.', 'Grace', 'steady'),
('When you feel behind,', 'God is not running you against anybody. The pace you are managing is the pace you are meant to be at today.', 'Look at a year ago rather than at somebody else now.', 'Patience', 'gentle'),
('When joy turns up unexpectedly,', 'let it land properly instead of bracing for what comes next. Good things are not a setup.', 'Receive it without flinching.', 'Joy', 'gentle'),
('When you are confused about a decision,', 'clarity usually arrives as a slow narrowing rather than a bright idea. Ruling things out is guidance too.', 'The boring sensible option is often the one that holds.', 'Wisdom', 'steady'),
('If you have stopped hoping,', 'hope is not optimism about outcomes. It is trusting the character of the one holding the outcome.', 'You do not have to feel hopeful to be held.', 'Hope while waiting', 'steady'),
('When you want to hide,', 'the instinct to cover up is old and human, and it has never once been necessary with him.', 'He already knows, and he has not left.', 'Grace', 'gentle'),
('When your work goes unnoticed,', 'faithfulness mostly looks like doing a dull task honestly when nobody checks.', 'It counted, and it was seen.', 'Purpose', 'steady'),
('When you are tempted to keep score,', 'measuring who owes whom will exhaust you long before it settles anything.', 'Put the ledger down.', 'Forgiveness', 'direct'),
('When peace feels impossible,', 'peace here does not mean the situation resolved. It means you are not facing it alone, which is different and often better.', 'You may still be worried tonight and still be held.', 'Peace under pressure', 'steady'),
('When you are starting something new,', 'the disorientation is normal and it does pass. Not knowing your way around yet is not incompetence.', 'He is already in the new place, in people you have not met.', 'Courage', 'steady'),
('When you feel like a burden,', 'the people who love you would rather carry something with you than find out later you did it alone.', 'Let somebody in this week.', 'Belonging', 'gentle'),
('When you cannot see the point,', 'the stretch that felt wasted is often exactly what makes you someone others can talk to later.', 'Nothing here is discarded.', 'Purpose', 'steady'),
('When you are angry,', 'anger is usually pain that has run out of patience. Bring the anger too; he can take all of it.', 'Say the true thing rather than the polite one.', 'Honesty', 'direct'),
('When you have been let down,', 'people will fail you, sometimes badly, and that is not evidence that God has.', 'Let this cost you less than it wants to.', 'Trust', 'steady'),
('When gratitude feels forced,', 'you are not required to feel thankful for what is hard. Notice something ordinary that went right instead.', 'Water that runs. A door that locks. Somebody who would answer.', 'Gratitude', 'gentle'),
('When the night is long,', 'whatever is unresolved now will still be unresolved in the morning, and you will be better equipped having slept.', 'Worrying is not the same as preparing.', 'Rest', 'gentle'),
('When you feel unforgivable,', 'the size of what you have done has never been the deciding factor. It was never a negotiation you were losing.', 'Come back. That is the whole invitation.', 'Grace', 'gentle'),
('When you have to say a hard thing,', 'wait until you are calm rather than until you feel ready, because ready may not arrive.', 'Then say the true thing kindly.', 'Wisdom', 'direct'),
('When everything feels uncertain,', 'certainty was never what you were promised. Presence was.', 'You can walk without a map if you are not walking alone.', 'Trust', 'steady'),
('When you feel replaceable,', 'you are not a role that somebody else could fill equally well. You are not interchangeable to him.', 'That is true today, whatever your week looked like.', 'Worth', 'gentle'),
('When shame speaks up,', 'notice the difference between conviction, which points at a thing you did, and shame, which points at you.', 'Only one of those is from God.', 'Grace', 'steady'),
('When you have nothing to bring,', 'he is not only available to the capable and the upbeat. Turning up empty is still turning up.', 'Bring the nothing. It is enough.', 'God''s love', 'gentle'),
('When the good news feels far away,', 'it is not less true on the days you cannot feel it. Truth does not run on your mood.', 'Hold on loosely today and let it hold you.', 'Faith', 'steady')
on conflict do nothing;

-- ---------- 20260912_verse_only.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Drop the reminder from the daily verse.
--
-- The feature is now just the verse. Today's Reminder is gone from the page, so
-- an assignment no longer needs a reminder attached to it.
--
-- The reminder tables, the written library and the generator are left in place
-- rather than dropped. They cost nothing while unused, they hold ninety pieces
-- of writing, and bringing the feature back later is then a matter of showing a
-- column again rather than rebuilding it. Nothing reads them now.

alter table public.daily_assignments alter column reminder_id drop not null;

-- Without a reminder, what stops two people getting the same verse today is
-- nothing: that was deliberate and stays that way. What still holds is one
-- assignment per reader per day, and a reader not seeing the same verse twice
-- until they have seen everything.
create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 20;

      if is_member then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random()
        limit 1;

        -- Seen everything: allow a repeat rather than showing nothing.
        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
        -- Visitors still only meet the welcoming verses, with no fallback to
        -- an untagged one.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1 from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1 from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random() limit 1;
        end if;
      end if;

      exit when v_id is null;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, p_day, 'verse')
      on conflict do nothing
      returning id into made;

      if made is null then
        -- A concurrent request for this same reader won the race; read it back
        -- rather than drawing again.
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v on v.id = a.verse_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

drop function if exists public.my_daily_content();
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    auth.uid(), null, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;

drop function if exists public.visitor_daily_content(uuid);
create or replace function public.visitor_daily_content(p_visitor uuid)
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    null, p_visitor, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.visitor_daily_content(uuid) from public;
grant execute on function public.visitor_daily_content(uuid) to anon, authenticated;

-- ---------- 20260912_verses_needing_reminders.sql ----------
-- Which verses most need a reminder written for them.
--
-- Ordered by how few approved reminders they already hold, so coverage spreads
-- rather than deepening on verses that are already well served. A verse with
-- nothing approved is one the daily draw has to skip over, so those come first.
-- The random tiebreak stops the same verses being chosen on every run.

create or replace function public.verses_needing_reminders(p_limit int default 20)
returns table (id uuid, reference text, verse_text text, approved bigint)
language sql
security definer
set search_path = public
stable
as $$
  select v.id, v.reference, v.verse_text,
         count(r.id) filter (where r.status = 'active') as approved
  from public.daily_verses v
  left join public.daily_reminders r on r.verse_id = v.id
  where v.status = 'active' and v.devotional
  group by v.id, v.reference, v.verse_text
  order by approved asc, random()
  limit greatest(1, least(p_limit, 200));
$$;

revoke all on function public.verses_needing_reminders(int) from public;
grant execute on function public.verses_needing_reminders(int) to authenticated;

-- ---------- 20260912_verses_topics_visitors.sql ----------
-- Daily verse: per-reader randomisation, verse topics, visitor mode.
--
-- WHAT CHANGES AND WHY
--
-- 1. There is no global verse of the day any more. The unique index on
--    (assigned_on, verse_id) is dropped, so two people may hold the same verse
--    on the same day. What they may never share is a reminder.
--
-- 2. Visitors get an assignment too, identified by a server-generated id in an
--    HttpOnly cookie rather than by anything the browser can choose for itself.
--    Exactly one of user_id and visitor_id is set, enforced by a check.
--
-- 3. Verses carry structured fields (book, book_order, chapter, verse,
--    testament) so they can be ordered, filtered and joined to topics.
--
-- 4. Topics are a normalised join table. Visitors only ever see verses tagged
--    with the welcoming topics, and never fall back to an untagged verse.
--
-- ON SCRIPTURE TEXT
--
-- The stored text is the World English Bible, which is public domain. The ESV
-- is copyrighted by Crossway and its API is licensed for displaying passages,
-- not for reproducing the translation, which is why it caps a query at 500
-- verses. Storing all 31,102 ESV verses would be a copy of the whole work, so
-- the corpus stays WEB and ESV wording is fetched live for the single verse a
-- reader is shown. See docs/DAILY-VERSE.md.

-- ---------------------------------------------------------------------------
-- 1. Structured verse fields
-- ---------------------------------------------------------------------------

alter table public.daily_verses
  add column if not exists book       text,
  add column if not exists book_order smallint,
  add column if not exists chapter    smallint,
  add column if not exists verse      smallint,
  add column if not exists testament  text check (testament in ('OT', 'NT')),
  add column if not exists updated_at timestamptz not null default now();

-- Backfill from the reference already stored, e.g. "1 John 4:19".
update public.daily_verses
set book    = substring(reference from '^(.*?) [0-9]+:[0-9]+'),
    chapter = (substring(reference from ' ([0-9]+):[0-9]+'))::smallint,
    verse   = (substring(reference from ':([0-9]+)'))::smallint
where book is null and reference ~ '^.+ [0-9]+:[0-9]+';

create unique index if not exists daily_verses_bcv_uniq
  on public.daily_verses (book, chapter, verse)
  where book is not null;

create index if not exists daily_verses_order_idx
  on public.daily_verses (book_order, chapter, verse);

-- ---------------------------------------------------------------------------
-- 2. Topics
--
-- A normalised join table rather than an array column: a verse belongs to
-- several topics, topics are queried by name, and the set will grow. An array
-- would need a GIN index and string matching to do the same job less clearly.
-- ---------------------------------------------------------------------------

create table if not exists public.verse_topic_kinds (
  slug        text primary key,
  label       text not null,
  -- Whether a verse carrying this topic may be shown to somebody who has not
  -- signed up. These are the welcoming themes only.
  visitor_safe boolean not null default false
);

insert into public.verse_topic_kinds (slug, label, visitor_safe) values
  ('love',            'Loved by God',        true),
  ('acceptance',      'Accepted',            true),
  ('identity',        'Identity in Christ',  true),
  ('grace',           'Grace',               true),
  ('adoption',        'Adopted',             true),
  ('no-condemnation', 'No condemnation',     true),
  ('worth',           'Valued',              true),
  ('welcome',         'Welcomed',            true),
  ('belonging',       'Belonging',           true),
  ('cherished',       'Cherished',           true),
  ('mercy',           'Mercy',               true),
  ('reconciliation',  'Reconciled',          true),
  ('comfort',         'Comfort',             false),
  ('courage',         'Courage',             false),
  ('patience',        'Patience',            false),
  ('wisdom',          'Wisdom',              false)
on conflict (slug) do nothing;

create table if not exists public.verse_topics (
  verse_id uuid not null references public.daily_verses(id) on delete cascade,
  topic    text not null references public.verse_topic_kinds(slug) on delete cascade,
  primary key (verse_id, topic)
);

create index if not exists verse_topics_topic_idx on public.verse_topics (topic);

-- ---------------------------------------------------------------------------
-- 3. Reminders belong to a verse again, and carry a focus tag
--
-- The previous model made reminders general and shared across verses. This
-- returns them to a single verse, which is what allows a verse to accumulate
-- thousands of reminders over time through generation.
-- ---------------------------------------------------------------------------

alter table public.daily_reminders
  add column if not exists verse_id   uuid references public.daily_verses(id) on delete cascade,
  add column if not exists focus_tag  text,
  add column if not exists template_id uuid,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists daily_reminders_verse_unused_idx
  on public.daily_reminders (verse_id) where status = 'active';

-- ---------------------------------------------------------------------------
-- 4. Assignments: per reader, not per day globally
-- ---------------------------------------------------------------------------

alter table public.daily_assignments
  add column if not exists visitor_id uuid;

alter table public.daily_assignments alter column user_id drop not null;

-- No global verse of the day. Two people may hold the same verse today.
alter table public.daily_assignments drop constraint if exists one_verse_per_day;
alter table public.daily_assignments drop constraint if exists one_per_user_per_day;
alter table public.daily_assignments drop constraint if exists pairing_used_once;
alter table public.daily_assignments drop constraint if exists reminder_seen_once_per_user;
alter table public.daily_assignments drop constraint if exists reminder_used_once;

-- Exactly one identity per assignment.
alter table public.daily_assignments drop constraint if exists one_identity;
alter table public.daily_assignments
  add constraint one_identity check (
    (user_id is not null and visitor_id is null)
    or (user_id is null and visitor_id is not null)
  );

-- Partial uniques, because one of the two columns is always null.
create unique index if not exists assignments_user_day_uniq
  on public.daily_assignments (user_id, assigned_on) where user_id is not null;

create unique index if not exists assignments_visitor_day_uniq
  on public.daily_assignments (visitor_id, assigned_on) where visitor_id is not null;

-- A reminder is spent permanently, whoever spent it.
create unique index if not exists assignments_reminder_uniq
  on public.daily_assignments (reminder_id);

-- ---------- 20260912_visitor_topic_seed.sql ----------
-- Verses a visitor may be shown.
--
-- Curated rather than exhaustive, and deliberately so. These are references
-- widely read as speaking about being loved, accepted, welcomed or not
-- condemned. Tagging is an editorial judgement about theme, not a claim that
-- every verse here carries identical theological weight, and the list is meant
-- to be extended.
--
-- Matching is by reference, so a verse only gets tagged once it exists in
-- daily_verses. Running this again after a fuller import picks up whatever was
-- missing, which is why it is written as an idempotent insert from a values
-- list rather than as fixed ids.
--
-- TO EXTEND: add rows below and re-run. To add a new topic, insert it into
-- verse_topic_kinds first and set visitor_safe according to whether a stranger
-- to the church should meet that idea before anything else.

insert into public.verse_topics (verse_id, topic)
select v.id, t.topic
from (values
  -- Loved
  ('John 3:16', 'love'), ('Romans 5:8', 'love'), ('1 John 4:9', 'love'),
  ('1 John 4:10', 'love'), ('1 John 4:19', 'love'), ('Jeremiah 31:3', 'love'),
  ('Zephaniah 3:17', 'love'), ('Psalms 136:1', 'love'), ('Ephesians 2:4', 'love'),
  ('Romans 8:38', 'love'), ('Romans 8:39', 'love'), ('John 15:9', 'love'),
  ('Deuteronomy 7:9', 'love'), ('Isaiah 54:10', 'love'), ('Lamentations 3:22', 'love'),
  ('Psalms 103:11', 'love'), ('Titus 3:4', 'love'), ('John 13:1', 'love'),

  -- Accepted and welcomed
  ('Romans 15:7', 'acceptance'), ('John 6:37', 'welcome'), ('Matthew 11:28', 'welcome'),
  ('Luke 15:20', 'welcome'), ('Isaiah 1:18', 'acceptance'), ('Revelation 22:17', 'welcome'),
  ('Ephesians 1:6', 'acceptance'), ('Hebrews 4:16', 'welcome'), ('Psalms 27:10', 'welcome'),
  ('Isaiah 55:1', 'welcome'), ('Matthew 9:13', 'acceptance'), ('Luke 19:10', 'welcome'),

  -- Adopted and belonging
  ('John 1:12', 'adoption'), ('Romans 8:15', 'adoption'), ('Romans 8:16', 'adoption'),
  ('Galatians 4:5', 'adoption'), ('Galatians 4:7', 'adoption'), ('Ephesians 1:5', 'adoption'),
  ('1 John 3:1', 'adoption'), ('Ephesians 2:19', 'belonging'), ('1 Peter 2:9', 'belonging'),
  ('1 Peter 2:10', 'belonging'), ('Isaiah 43:1', 'belonging'), ('John 10:14', 'belonging'),
  ('Psalms 100:3', 'belonging'), ('1 Corinthians 12:27', 'belonging'),

  -- Valued and cherished
  ('Psalms 139:13', 'worth'), ('Psalms 139:14', 'worth'), ('Matthew 10:31', 'worth'),
  ('Luke 12:7', 'worth'), ('Isaiah 43:4', 'cherished'), ('Matthew 6:26', 'worth'),
  ('Ephesians 2:10', 'worth'), ('Psalms 8:5', 'worth'), ('Isaiah 49:16', 'cherished'),
  ('Deuteronomy 14:2', 'cherished'), ('Song of Solomon 4:7', 'cherished'),

  -- Grace and mercy
  ('Ephesians 2:8', 'grace'), ('Ephesians 2:9', 'grace'), ('Titus 3:5', 'grace'),
  ('2 Corinthians 12:9', 'grace'), ('Hebrews 4:15', 'mercy'), ('Lamentations 3:23', 'mercy'),
  ('Psalms 51:1', 'mercy'), ('Micah 7:18', 'mercy'), ('Luke 6:36', 'mercy'),
  ('Psalms 103:8', 'mercy'), ('Joel 2:13', 'mercy'), ('Exodus 34:6', 'mercy'),

  -- No condemnation
  ('Romans 8:1', 'no-condemnation'), ('John 8:11', 'no-condemnation'),
  ('Psalms 103:12', 'no-condemnation'), ('Isaiah 43:25', 'no-condemnation'),
  ('Micah 7:19', 'no-condemnation'), ('1 John 1:9', 'no-condemnation'),
  ('Colossians 2:14', 'no-condemnation'), ('Hebrews 8:12', 'no-condemnation'),
  ('John 3:17', 'no-condemnation'), ('Romans 8:34', 'no-condemnation'),

  -- Reconciled
  ('2 Corinthians 5:18', 'reconciliation'), ('2 Corinthians 5:19', 'reconciliation'),
  ('Colossians 1:20', 'reconciliation'), ('Colossians 1:22', 'reconciliation'),
  ('Romans 5:10', 'reconciliation'), ('Ephesians 2:13', 'reconciliation'),
  ('Ephesians 2:14', 'reconciliation'),

  -- Identity
  ('2 Corinthians 5:17', 'identity'), ('Galatians 2:20', 'identity'),
  ('Colossians 3:3', 'identity'), ('1 Peter 2:5', 'identity'),
  ('Philippians 3:20', 'identity'), ('John 15:15', 'identity')
) as t(reference, topic)
join public.daily_verses v on v.reference = t.reference
on conflict do nothing;

-- ---------- 20260912_whole_reminders.sql ----------
-- Reminders written whole, not assembled from parts.
--
-- The previous generator stitched two template fragments together to reach the
-- fifty word minimum. It produced text like "you did. you do not have to find
-- the right words for it": a lowercase sentence start, because the fragment was
-- written to follow a clause, and two unrelated thoughts with nothing joining
-- them. Hitting a word count is not the same as writing a sentence.
--
-- Each template is now one finished reminder of the right length, in plain
-- language, with the grammar already correct. Generation picks one and stores
-- it against a verse. Nothing is concatenated, so nothing can come out
-- ungrammatical.
--
-- Capacity is templates multiplied by verses rather than pairs multiplied by
-- verses. Sixty templates against 13,239 eligible verses is roughly 794,000
-- reminders, and every template added multiplies that again. Fewer, better
-- reminders is the right trade: a reader meets one a day, and one that reads
-- badly is worse than none.

alter table public.reminder_templates
  add column if not exists text text;

update public.reminder_templates
set text = opening || ' ' || body || ' ' || closing
where text is null;

alter table public.reminder_templates alter column text set not null;

-- The old parts are no longer used for composition.
alter table public.reminder_templates alter column opening drop not null;
alter table public.reminder_templates alter column body    drop not null;
alter table public.reminder_templates alter column closing drop not null;

-- Start again. The rows already here were assembled by the old routine and read
-- badly, so they are cleared before the stricter rules are applied rather than
-- being migrated into a shape they cannot satisfy.
delete from public.daily_assignments;
delete from public.daily_reminders;
delete from public.reminder_templates;

-- A template is now a complete reminder, so it must satisfy the same rules the
-- stored reminder does. Checking here means a badly written template is
-- rejected when it is added rather than discovered by a reader.
alter table public.reminder_templates drop constraint if exists template_length;
alter table public.reminder_templates
  add constraint template_length check (
    text is null
    or array_length(regexp_split_to_array(trim(text), '\s+'), 1) between 50 and 90
  );

alter table public.reminder_templates drop constraint if exists template_starts_capital;
alter table public.reminder_templates
  add constraint template_starts_capital check (text is null or text ~ '^[A-Z]');

alter table public.reminder_templates drop constraint if exists template_ends_stop;
alter table public.reminder_templates
  add constraint template_ends_stop check (text is null or text ~ '[.!?]$');

alter table public.reminder_templates alter column opening set default '';
alter table public.reminder_templates alter column body    set default '';
alter table public.reminder_templates alter column closing set default '';

-- Uniqueness moves to the finished text. The old index hashed the three part
-- columns, which are unused now, so every new template hashed identically and
-- collided with the first one inserted.
drop index if exists reminder_templates_uniq;
create unique index if not exists reminder_templates_text_uniq
  on public.reminder_templates (md5(lower(regexp_replace(text, '\s+', ' ', 'g'))));

-- ---------- 20260913_daily_uses_passage.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Restore passage expansion for the daily verse.
--
-- 20260912_verse_only.sql redefined claim_daily_for to return the raw single
-- verse from daily_verses, bypassing passage_for(). That put stranded verses
-- like Mark 11:5 back on the page. This rebuilds claim_daily_for identically
-- except the final return joins passage_for(), same as 20260912_passages.sql.

create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 20;

      if is_member then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1 from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1 from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random() limit 1;
        end if;
      end if;

      exit when v_id is null;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, p_day, 'verse')
      on conflict do nothing
      returning id into made;

      if made is null then
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, p.reference, p.passage_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  cross join lateral public.passage_for(a.verse_id) p
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

-- ---------- 20260913_list_leaders_with_title.sql ----------
drop function if exists public.list_leaders();
drop function if exists public.claim_daily_for(uuid, uuid, date);
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
-- Include the title in list_leaders so the signup dropdown can show Head
-- Pastor, Pastor and other roles beside the name. Members can then pick a
-- pastor without having to know which of the listed people is one.
drop function if exists public.list_leaders();
create or replace function public.list_leaders()
returns table (id uuid, full_name text, title text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.title
  from public.profiles p
  where p.is_leader = true
    and p.account_status = 'approved'
    and p.is_hidden = false
  order by
    -- Pastors first, then everyone else, then alphabetical inside each band.
    case
      when p.title ilike 'head pastor%' then 0
      when p.title ilike 'pastor%'      then 1
      else 2
    end,
    p.full_name;
$$;

revoke all on function public.list_leaders() from public;
grant execute on function public.list_leaders() to anon, authenticated;

-- ---------- 20260913_site_content.sql ----------
-- Editable site copy.
--
-- Blocks of text that used to live in JSX are keyed by a stable slug and stored
-- here so super admins can edit them from /admin/content without a deploy.
-- The slug is the contract: code renders getContent('some.slug', fallback), and
-- if the row is missing the hard-coded fallback ships instead. That keeps every
-- page renderable even before an editor has visited the admin panel, and stops
-- a mistyped slug from leaving a blank hole on production.

create table if not exists public.site_content (
  slug         text primary key,
  body         text not null default '',
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null
);

comment on table public.site_content is
  'Editable copy blocks keyed by slug. Rendered by getContent() with a code-side fallback.';

alter table public.site_content enable row level security;

-- Everyone reads: the copy is public.
drop policy if exists site_content_read on public.site_content;
create policy site_content_read on public.site_content
  for select using (true);

-- Only super_admin writes. Admins do not: this is copy that speaks for the
-- church, and the deliberate narrowing keeps that decision with one person.
drop policy if exists site_content_write on public.site_content;
create policy site_content_write on public.site_content
  for all
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );

grant select on public.site_content to anon, authenticated;
grant insert, update, delete on public.site_content to authenticated;

-- ---------- 20260914_promotions_and_system_posts.sql ----------
-- Promotions from Disciple to Leader and Leader to Pastor, celebrated as a
-- feed post written by the church rather than by the promoter, and a
-- notification kind so everybody hears about it.

-- 1. Feed posts can now be authored "by the church". A real profile still owns
--    the row so RLS and moderation stay consistent, but the byline renders as
--    Amazing Church Philippines and its logo instead of that profile.
alter table public.posts add column if not exists is_system boolean not null default false;

-- 2. New notification kinds. Both the promoted person and every leader are
--    told, and the promotion post's insert also notifies through the existing
--    'new_post' path via triggers if they exist.
alter type public.notification_kind add value if not exists 'promoted';

-- 3. Do the promotion transactionally. This exists so the check that the
--    caller is allowed to promote lives beside the write, and so the post +
--    notifications land in one round trip.
create or replace function public.promote_member(
  p_target uuid,
  p_to     text  -- 'Leader' or 'Pastor'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_row  record;
  target_row record;
  new_title  text := p_to;
  message    text;
  leader_row record;
begin
  if new_title not in ('Leader', 'Pastor') then
    raise exception 'promote_member: target must be Leader or Pastor';
  end if;

  select p.id, p.role, p.title, p.full_name
    into actor_row
  from public.profiles p where p.id = auth.uid();
  if not found then
    raise exception 'not signed in';
  end if;

  select p.id, p.title, p.is_leader, p.full_name
    into target_row
  from public.profiles p where p.id = p_target;
  if not found then
    raise exception 'target not found';
  end if;

  -- What promotion is this? A Disciple becomes a Leader; a Leader becomes a
  -- Pastor. Anything else is rejected rather than silently normalised.
  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

  -- Who is allowed to promote? Super Admin bypasses. Otherwise use the
  -- actor's church title:
  --   Disciple -> Leader : Head Pastor, Pastor, Leader
  --   Leader   -> Pastor : Head Pastor, Pastor (never Leader)
  if actor_row.role <> 'super_admin' then
    if new_title = 'Leader' then
      if lower(coalesce(actor_row.title, '')) not in ('head pastor', 'pastor', 'leader') then
        raise exception 'not allowed to promote to Leader';
      end if;
    elsif new_title = 'Pastor' then
      if lower(coalesce(actor_row.title, '')) not in ('head pastor', 'pastor') then
        raise exception 'only Head Pastor or Pastor can promote to Pastor';
      end if;
    end if;
  end if;

  -- Apply the promotion.
  update public.profiles
     set is_leader = true,
         title     = new_title
   where id = target_row.id;

  -- The celebratory message. Warm, biblical in tone, deliberately not a
  -- quoted verse (chapter-and-verse quotations belong on the Daily Verse card,
  -- not stapled onto a personal announcement).
  if new_title = 'Leader' then
    message := format(
      'Rejoice with us. Today we set apart %s as a Leader in the household. ' ||
      'The Lord has been shaping this heart in quiet ways for a long time, and we bless ' ||
      'this next step of taking others under their care. May grace multiply, may wisdom ' ||
      'be given daily, and may the flock entrusted to them flourish.',
      target_row.full_name
    );
  else
    message := format(
      'Rejoice with us. Today we recognize %s as a Pastor in the household. ' ||
      'They have shepherded faithfully as a Leader, and we entrust to them a wider circle ' ||
      'of care. May the Chief Shepherd strengthen them, may their family be knit tightly ' ||
      'in love, and may every soul under their watch be brought closer to Christ.',
      target_row.full_name
    );
  end if;

  -- One feed post per promotion, authored by the actor's row for RLS reasons
  -- but flagged as a system post so the byline renders as the church.
  insert into public.posts (author_id, body, status, is_system)
  values (actor_row.id, message, 'approved', true);

  -- Notify the promoted person and every current leader. The actor is not
  -- excluded — a Head Pastor promoting a Leader still gets the announcement
  -- so it appears in their bell like anyone else's.
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, actor_row.id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false
     and (p.id = target_row.id or p.is_leader = true);
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;
