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
