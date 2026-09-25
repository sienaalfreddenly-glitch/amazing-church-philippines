-- The church as its own account.
--
-- Feed posts, discussion posts, and every future system announcement (like a
-- promotion) run through this profile. Because it is a real row with a real
-- auth.users backing it, everything downstream — RLS on posts, mention
-- notifications, avatar joins on notifications — reads a real author rather
-- than needing to special case an is_system flag everywhere.
--
-- The uuid is fixed so app code can reference it as a constant. The seeded
-- avatar is /logo.png (the church logo already sits in /public). Everything
-- but this row is hidden from directories: is_hidden = true keeps it out of
-- the leaders list, the org chart, and every non-super admin view.

do $$
declare
  church_id uuid := '11111111-1111-4111-8111-111111111111';
begin
  -- auth.users first: profiles.id has an FK to it. No password is set; the
  -- account cannot log in, and there is no need to. Super admins edit its
  -- profile from /admin/church.
  insert into auth.users (
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  )
  values (
    church_id, 'authenticated', 'authenticated',
    'church@amazing-church-philippines.local',
    now(), '{}'::jsonb,
    jsonb_build_object('full_name', 'Amazing Church Philippines'),
    now(), now()
  )
  on conflict (id) do nothing;

  insert into public.profiles (
    id, full_name, email, role, account_status, is_leader, is_hidden,
    avatar_url, must_change_password
  )
  values (
    church_id, 'Amazing Church Philippines',
    'church@amazing-church-philippines.local',
    'user', 'approved', false, true,
    '/logo.png', false
  )
  on conflict (id) do update
    set full_name  = coalesce(public.profiles.full_name, excluded.full_name),
        avatar_url = coalesce(public.profiles.avatar_url, excluded.avatar_url),
        account_status = 'approved',
        is_hidden      = true;
end $$;

-- A helper the RPC uses, so the id is not hardcoded in two places.
create or replace function public.church_profile_id()
returns uuid
language sql
immutable
as $$ select '11111111-1111-4111-8111-111111111111'::uuid $$;

grant execute on function public.church_profile_id() to authenticated, anon;

-- Rewrite promote_member: author the post as the church, mention the
-- promoted person as a real @-tag, and speak in gender-neutral pronouns.
create or replace function public.promote_member(
  p_target uuid,
  p_to     text
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
  church_id  uuid := public.church_profile_id();
  mention    text;
  templates  text[];
  message    text;
begin
  if new_title not in ('Leader', 'Pastor') then
    raise exception 'promote_member: target must be Leader or Pastor';
  end if;

  select p.id, p.role, p.title, p.full_name
    into actor_row
  from public.profiles p where p.id = auth.uid();
  if not found then raise exception 'not signed in'; end if;

  select p.id, p.title, p.is_leader, p.full_name
    into target_row
  from public.profiles p where p.id = p_target;
  if not found then raise exception 'target not found'; end if;

  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

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

  update public.profiles
     set is_leader = true, title = new_title
   where id = target_row.id;

  mention := '@' || target_row.full_name;

  -- Warm, plain, gender-neutral (they / them / their). One of five picked
  -- at random per promotion so back-to-back posts do not read identically.
  if new_title = 'Leader' then
    templates := array[
      format('Big news — %s is now a Leader in our church. They''ll be walking with a small group, listening, praying with them, and checking in when life gets heavy. Cheer them on!', mention),
      format('Today %s steps up as a Leader. That means they''ll be looking after a small circle of our people — the everyday stuff, the hard stuff, and the good stuff. Give them a warm welcome.', mention),
      format('Happy day. %s is one of our Leaders now. They get to walk alongside a few of us, pray, listen, and point us to Jesus. So proud of this next step.', mention),
      format('Please welcome %s as a Leader. They''ll take a small group under their wing and just be present for them. Kind messages very welcome.', mention),
      format('One to celebrate: %s is now a Leader. They''ll help a small group of members feel known and cared for. Send love their way today.', mention)
    ];
  else
    templates := array[
      format('News to celebrate. %s is now a Pastor. They''ve been faithful as a Leader, and now they take on a bigger family here. Keep them in your prayers.', mention),
      format('Today we recognise %s as a Pastor. They''ve been quietly serving as a Leader for a while, and now they get to shepherd a wider circle. Thank God with us.', mention),
      format('%s steps into a Pastor role today. That''s more people to care for, more decisions to walk through, more praying to do. They''ll do beautifully with your support.', mention),
      format('Big moment: %s is now one of our Pastors. They have been shepherding a small group so faithfully, and it''s time for a bigger flock. Congratulate them.', mention),
      format('Please pray for %s — they''ve just been made a Pastor. New weight, new joy, same heart. Cheer them on and back them up.', mention)
    ];
  end if;

  message := templates[1 + floor(random() * array_length(templates, 1))::int];

  -- Author the post as the church. mentions carries the promoted person's
  -- id so RenderMentions styles their name and the mention trigger fires a
  -- 'mention' notification for them. That notification's actor is the
  -- church profile, so the bell reads 'Amazing Church Philippines mentioned
  -- you in a post' — never the promoter's name.
  insert into public.posts (author_id, body, status, is_system, mentions)
  values (church_id, message, 'approved', true, array[target_row.id]);

  -- 'promoted' notification to every approved, non-hidden member. The
  -- actor is still the church, and the bell renders promoted rows from the
  -- church profile's avatar and name.
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, church_id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false;
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;

-- A tiny RPC so super admins can update the church profile's avatar and
-- name from the admin panel without needing service-role in the browser.
create or replace function public.update_church_profile(
  p_full_name  text,
  p_avatar_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  church_id  uuid := public.church_profile_id();
begin
  select role into actor_role from public.profiles where id = auth.uid();
  if actor_role is distinct from 'super_admin' then
    raise exception 'only a super admin may edit the church account';
  end if;
  update public.profiles
     set full_name  = coalesce(nullif(p_full_name, ''),  full_name),
         avatar_url = coalesce(nullif(p_avatar_url, ''), avatar_url)
   where id = church_id;
end;
$$;

revoke all on function public.update_church_profile(text, text) from public;
grant execute on function public.update_church_profile(text, text) to authenticated;
