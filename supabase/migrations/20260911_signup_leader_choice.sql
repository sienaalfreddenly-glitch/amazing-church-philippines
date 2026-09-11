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
