-- Polish the promotion flow after the first live run:
--
-- * The mention notification kept saying "<Actor> mentioned you in a post"
--   because the RPC put the promoted person's id in posts.mentions. Drop
--   that so nothing fires, and also teach notify_post_mentions to skip
--   is_system posts as a second line of defence.
-- * Messages were too churchy and always the same. Ship a small library
--   of plainer, warmer copy and pick one at random per promotion, so a
--   feed with several promotions does not read like a mail merge.
-- * The name still needs to be highlighted in the body, so RenderMentions
--   can style it, but the id no longer rides in the mentions array.

create or replace function public.notify_post_mentions() returns trigger
language plpgsql security definer set search_path = public as $$
declare m uuid; ent text;
begin
  if coalesce(new.is_system, false) then return new; end if;
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
end $$;

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

  -- @Name so RenderMentions styles the name, no uuid in mentions so no
  -- mention notification is generated.
  mention := '@' || target_row.full_name;

  -- Warm, plain, layman copy. Pick one at random so repeats do not stack up
  -- identical wording in the feed.
  if new_title = 'Leader' then
    templates := array[
      format('Big news — %s is now a Leader in our church. She''ll be walking with a small group, listening, praying with them, and checking in when life gets heavy. Cheer her on!', mention),
      format('Today %s steps up as a Leader. That means she''ll be looking after a small circle of our people — the everyday stuff, the hard stuff, and the good stuff. Give her a warm welcome.', mention),
      format('Happy day. %s is one of our Leaders now. She gets to walk alongside a few of us, pray, listen, and point us to Jesus. So proud of this next step.', mention),
      format('Please welcome %s as a Leader. She''ll take a small group under her wing and just be present for them. Kind messages very welcome.', mention),
      format('One to celebrate: %s is now a Leader. She''ll help a small group of members feel known and cared for. Send love her way today.', mention)
    ];
  else
    templates := array[
      format('News to celebrate. %s is now a Pastor. She''s been faithful as a Leader, and now she takes on a bigger family here. Keep her in your prayers.', mention),
      format('Today we recognise %s as a Pastor. She''s been quietly serving as a Leader for a while, and now she gets to shepherd a wider circle. Thank God with us.', mention),
      format('%s steps into a Pastor role today. That''s more people to care for, more decisions to walk through, more praying to do. She''ll do beautifully with your support.', mention),
      format('Big moment: %s is now one of our Pastors. She has been shepherding a small group so faithfully, and it''s time for a bigger flock. Congratulate her.', mention),
      format('Please pray for %s — she''s just been made a Pastor. New weight, new joy, same heart. Cheer her on and back her up.', mention)
    ];
  end if;

  message := templates[1 + floor(random() * array_length(templates, 1))::int];

  insert into public.posts (author_id, body, status, is_system, mentions)
  values (actor_row.id, message, 'approved', true, '{}'::uuid[]);

  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, actor_row.id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false;
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;
