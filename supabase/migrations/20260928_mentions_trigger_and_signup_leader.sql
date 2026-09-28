-- 1. notify_post_mentions runs on both posts and discussions but read
--    new.is_system, a column only posts has. plpgsql fails on a missing field,
--    so every new discussion errored with: record "new" has no field
--    "is_system". Read it through jsonb, which yields null when absent.
--
-- 2. The 'new_member' signup notification now carries the chosen leader's id
--    and name, so the bell can say whether the newcomer has a leader.
--
-- Safe to re-run.

create or replace function public.notify_post_mentions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare m uuid; ent text;
begin
  if coalesce((to_jsonb(new)->>'is_system')::boolean, false) then return new; end if;
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
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_leader uuid;
  leader_name   text;
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
    select full_name into leader_name from public.profiles
     where id = chosen_leader and is_leader = true and account_status = 'approved';
    if not found then
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
         jsonb_build_object(
           'full_name', display_name, 'email', new.email,
           'leader_id', chosen_leader, 'leader_name', leader_name
         )
    from public.profiles p
   where p.account_status = 'approved'
     and p.id <> new.id
     and (p.role in ('admin', 'super_admin', 'moderator') or p.id = chosen_leader)
     -- Already told via unassigned_member above.
     and not (chosen_leader is null and p.is_leader);

  return new;
end;
$$;
