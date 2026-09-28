-- Signups only notified leaders, and only when the newcomer picked no leader.
-- Admins, who approve new accounts, were never told, and a newcomer who picked
-- a leader notified nobody at all. Now every signup also sends 'new_member' to
-- all staff (admin, super_admin, moderator) and to the leader they chose.
-- Anyone already receiving 'unassigned_member' for this signup is skipped so
-- nobody gets two alerts. Safe to re-run.

alter type public.notification_kind add value if not exists 'new_member';

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
  display_name  text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
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
    display_name,
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
        jsonb_build_object('full_name', display_name, 'email', new.email)
      );
    end loop;
  end if;

  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, new.id, 'new_member', 'profile', new.id,
         jsonb_build_object('full_name', display_name, 'email', new.email)
    from public.profiles p
   where p.account_status = 'approved'
     and p.id <> new.id
     and (p.role in ('admin', 'super_admin', 'moderator') or p.id = chosen_leader)
     -- Already told via unassigned_member above.
     and not (chosen_leader is null and p.is_leader);

  return new;
end;
$$;
