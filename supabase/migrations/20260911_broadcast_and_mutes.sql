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
