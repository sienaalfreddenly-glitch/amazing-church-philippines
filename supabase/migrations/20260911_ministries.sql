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
