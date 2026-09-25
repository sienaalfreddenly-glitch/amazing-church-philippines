-- Two things:
--   1. Announcements the church posts (anything authored by the church that
--      is not a promotion) should notify every member. Promotions keep
--      their own targeted 'promoted' notification and are excluded from the
--      generic broadcast, so nobody gets two rows for the same event.
--   2. Super admins and moderators can post as the church without logging
--      in as it. A tiny SECURITY DEFINER wrapper checks their role and
--      inserts a post with author_id = church_profile_id().

-- Distinguish a promotion from any other church post so notify_new_post
-- knows when to stay quiet. system_kind = null on member posts, and
-- 'promotion' on the ones written by promote_member.
alter table public.posts add column if not exists system_kind text;

create or replace function public.notify_new_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if new.status is distinct from 'approved' then return new; end if;
  -- Promotions have their own targeted 'promoted' notification, so skip the
  -- generic broadcast for them; every other post — member or church — fans
  -- out to the household.
  if new.system_kind = 'promotion' then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

-- Redefine promote_member to stamp system_kind='promotion' on the post.
-- Body, mentions, notifications otherwise unchanged from the previous copy.
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

  select p.id, p.role, p.title, p.full_name into actor_row
    from public.profiles p where p.id = auth.uid();
  if not found then raise exception 'not signed in'; end if;

  select p.id, p.title, p.is_leader, p.full_name into target_row
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

  update public.profiles set is_leader = true, title = new_title
   where id = target_row.id;

  mention := '@' || target_row.full_name;

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

  insert into public.posts (author_id, body, status, is_system, system_kind, mentions)
  values (church_id, message, 'approved', true, 'promotion', array[target_row.id]);

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

-- Post as the church. The caller must be a super admin, admin, or moderator;
-- everyone else is refused. The row is inserted with author_id = the church
-- profile so notifications and the byline all read as the church. The
-- ordinary notify_new_post broadcast then fans it out to every member.
create or replace function public.post_as_church(
  p_body      text,
  p_title     text default null,
  p_media_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  new_id     uuid;
begin
  select role into actor_role from public.profiles where id = auth.uid();
  if actor_role is null or actor_role not in ('super_admin', 'admin', 'moderator') then
    raise exception 'only staff may post as the church';
  end if;
  if p_body is null or trim(p_body) = '' then
    raise exception 'body is required';
  end if;
  insert into public.posts (author_id, body, title, media_url, status, is_system)
  values (public.church_profile_id(), p_body, nullif(p_title, ''), nullif(p_media_url, ''), 'approved', true)
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.post_as_church(text, text, text) from public;
grant execute on function public.post_as_church(text, text, text) to authenticated;

-- Same for a discussion thread. Discussions carry the same shape but a
-- separate table.
create or replace function public.start_discussion_as_church(
  p_title text,
  p_body  text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  new_id     uuid;
begin
  select role into actor_role from public.profiles where id = auth.uid();
  if actor_role is null or actor_role not in ('super_admin', 'admin', 'moderator') then
    raise exception 'only staff may start a discussion as the church';
  end if;
  if p_title is null or trim(p_title) = '' or p_body is null or trim(p_body) = '' then
    raise exception 'title and body are required';
  end if;
  insert into public.discussions (author_id, title, body, status)
  values (public.church_profile_id(), p_title, p_body, 'approved')
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.start_discussion_as_church(text, text) from public;
grant execute on function public.start_discussion_as_church(text, text) to authenticated;
