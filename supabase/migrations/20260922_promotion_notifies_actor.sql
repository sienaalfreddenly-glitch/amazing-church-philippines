-- Make sure the promoter also receives the promotion notification.
--
-- The maintenance super-admin account is is_hidden=true so it stays out of
-- the household, but that also silently kept them out of the promotion
-- fanout: they pressed the button and then wondered why nothing landed in
-- their bell. Include the actor regardless of is_hidden.

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
  body_templates  text[];
  notif_templates text[];
  body_message    text;
  notif_message   text;
  new_post_id     uuid;
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
    body_templates := array[
      format('Big news — %s is now a Leader in our church. They''ll be walking with a small group, listening, praying with them, and checking in when life gets heavy. Cheer them on!', mention),
      format('Today %s steps up as a Leader. That means they''ll be looking after a small circle of our people — the everyday stuff, the hard stuff, and the good stuff. Give them a warm welcome.', mention),
      format('Happy day. %s is one of our Leaders now. They get to walk alongside a few of us, pray, listen, and point us to Jesus. So proud of this next step.', mention),
      format('Please welcome %s as a Leader. They''ll take a small group under their wing and just be present for them. Kind messages very welcome.', mention),
      format('One to celebrate: %s is now a Leader. They''ll help a small group of members feel known and cared for. Send love their way today.', mention)
    ];
    notif_templates := array[
      format('%s is now a Leader! Give them a warm welcome.', target_row.full_name),
      format('Say hi to our newest Leader, %s.', target_row.full_name),
      format('%s just stepped up as a Leader. Cheer them on.', target_row.full_name),
      format('New Leader in the house: %s. Pray for them.', target_row.full_name),
      format('%s is now a Leader in our church. Share the joy.', target_row.full_name)
    ];
  else
    body_templates := array[
      format('News to celebrate. %s is now a Pastor. They''ve been faithful as a Leader, and now they take on a bigger family here. Keep them in your prayers.', mention),
      format('Today we recognise %s as a Pastor. They''ve been quietly serving as a Leader for a while, and now they get to shepherd a wider circle. Thank God with us.', mention),
      format('%s steps into a Pastor role today. That''s more people to care for, more decisions to walk through, more praying to do. They''ll do beautifully with your support.', mention),
      format('Big moment: %s is now one of our Pastors. They have been shepherding a small group so faithfully, and it''s time for a bigger flock. Congratulate them.', mention),
      format('Please pray for %s — they''ve just been made a Pastor. New weight, new joy, same heart. Cheer them on and back them up.', mention)
    ];
    notif_templates := array[
      format('%s is now a Pastor! Praise God with us.', target_row.full_name),
      format('Congratulations to our newest Pastor, %s.', target_row.full_name),
      format('%s just became a Pastor. Please pray for them.', target_row.full_name),
      format('New Pastor in our family: %s. Give them your support.', target_row.full_name),
      format('Say hi to Pastor %s — they just got promoted!', target_row.full_name)
    ];
  end if;

  body_message  := body_templates[1 + floor(random() * array_length(body_templates, 1))::int];
  notif_message := notif_templates[1 + floor(random() * array_length(notif_templates, 1))::int];

  insert into public.posts (author_id, body, status, is_system, system_kind, mentions)
  values (church_id, body_message, 'approved', true, 'promotion', array[target_row.id])
  returning id into new_post_id;

  -- Everyone approved: the household plus the actor themselves. is_hidden
  -- is ignored for the actor, and only the church profile stays out — no
  -- point notifying the account that authored the post.
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, church_id, 'promoted', 'post', new_post_id,
         jsonb_build_object(
           'full_name', target_row.full_name,
           'to',        new_title,
           'message',   notif_message
         )
    from public.profiles p
   where p.account_status = 'approved'
     and p.id <> church_id
     and (p.is_hidden = false or p.id = actor_row.id);
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;
