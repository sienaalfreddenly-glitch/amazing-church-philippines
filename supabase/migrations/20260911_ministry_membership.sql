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
