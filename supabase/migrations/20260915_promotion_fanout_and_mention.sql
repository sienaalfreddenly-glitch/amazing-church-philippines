-- Three fixes to the promotion flow:
--   1. Skip the ordinary new_post broadcast for system posts. A promotion
--      already sends its own 'promoted' notification, and the extra "Name
--      posted" line looked like a leak of who pressed the button.
--   2. Send the 'promoted' notification to EVERY approved member, not just
--      leaders. The whole household should hear when somebody is raised up.
--   3. Rewrite the post body with an @-mention on the promoted person's
--      name (RenderMentions styles it) and include their id in posts.mentions
--      so their name links back to them in the feed.

-- 1. notify_new_post: skip system posts. The promotion RPC covers the fanout.
create or replace function public.notify_new_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if new.status is distinct from 'approved' then return new; end if;
  if coalesce(new.is_system, false) then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

-- 2 + 3. promote_member rewrite.
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
  message    text;
  mention    text;
begin
  if new_title not in ('Leader', 'Pastor') then
    raise exception 'promote_member: target must be Leader or Pastor';
  end if;

  select p.id, p.role, p.title, p.full_name
    into actor_row
  from public.profiles p where p.id = auth.uid();
  if not found then
    raise exception 'not signed in';
  end if;

  select p.id, p.title, p.is_leader, p.full_name
    into target_row
  from public.profiles p where p.id = p_target;
  if not found then
    raise exception 'target not found';
  end if;

  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

  -- Authorisation.
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

  -- The mention wraps the person's name so RenderMentions styles it and the
  -- reader can jump to their profile through their name in the post.
  mention := '@' || target_row.full_name;

  if new_title = 'Leader' then
    message := format(
      'Rejoice with us. Today we set apart %s as a Leader in the household. ' ||
      'The Lord has been shaping this heart in quiet ways for a long time, and we bless ' ||
      'this next step of taking others under their care. May grace multiply, may wisdom ' ||
      'be given daily, and may the flock entrusted to %s flourish.',
      mention, mention
    );
  else
    message := format(
      'Rejoice with us. Today we recognize %s as a Pastor in the household. ' ||
      '%s has shepherded faithfully as a Leader, and we entrust to %s a wider circle ' ||
      'of care. May the Chief Shepherd strengthen %s, may their family be knit tightly ' ||
      'in love, and may every soul under their watch be brought closer to Christ.',
      mention, mention, mention, mention
    );
  end if;

  -- Feed post: mention the promoted person, flag as a system post.
  insert into public.posts (author_id, body, status, is_system, mentions)
  values (actor_row.id, message, 'approved', true, array[target_row.id]);

  -- Notify EVERYONE approved and not hidden. Super Admins to Disciples all
  -- hear it. Actor is included too. Actor id is written for foreign-key
  -- integrity, but the client renders 'promoted' rows as coming from the
  -- church, not from whoever pressed the button.
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
