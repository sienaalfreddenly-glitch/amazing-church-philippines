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
