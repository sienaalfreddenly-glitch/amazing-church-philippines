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
