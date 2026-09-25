-- Promotions from Disciple to Leader and Leader to Pastor, celebrated as a
-- feed post written by the church rather than by the promoter, and a
-- notification kind so everybody hears about it.

-- 1. Feed posts can now be authored "by the church". A real profile still owns
--    the row so RLS and moderation stay consistent, but the byline renders as
--    Amazing Church Philippines and its logo instead of that profile.
alter table public.posts add column if not exists is_system boolean not null default false;

-- 2. New notification kinds. Both the promoted person and every leader are
--    told, and the promotion post's insert also notifies through the existing
--    'new_post' path via triggers if they exist.
alter type public.notification_kind add value if not exists 'promoted';

-- 3. Do the promotion transactionally. This exists so the check that the
--    caller is allowed to promote lives beside the write, and so the post +
--    notifications land in one round trip.
create or replace function public.promote_member(
  p_target uuid,
  p_to     text  -- 'Leader' or 'Pastor'
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
  leader_row record;
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

  -- What promotion is this? A Disciple becomes a Leader; a Leader becomes a
  -- Pastor. Anything else is rejected rather than silently normalised.
  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

  -- Who is allowed to promote? Super Admin bypasses. Otherwise use the
  -- actor's church title:
  --   Disciple -> Leader : Head Pastor, Pastor, Leader
  --   Leader   -> Pastor : Head Pastor, Pastor (never Leader)
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

  -- Apply the promotion.
  update public.profiles
     set is_leader = true,
         title     = new_title
   where id = target_row.id;

  -- The celebratory message. Warm, biblical in tone, deliberately not a
  -- quoted verse (chapter-and-verse quotations belong on the Daily Verse card,
  -- not stapled onto a personal announcement).
  if new_title = 'Leader' then
    message := format(
      'Rejoice with us. Today we set apart %s as a Leader in the household. ' ||
      'The Lord has been shaping this heart in quiet ways for a long time, and we bless ' ||
      'this next step of taking others under their care. May grace multiply, may wisdom ' ||
      'be given daily, and may the flock entrusted to them flourish.',
      target_row.full_name
    );
  else
    message := format(
      'Rejoice with us. Today we recognize %s as a Pastor in the household. ' ||
      'They have shepherded faithfully as a Leader, and we entrust to them a wider circle ' ||
      'of care. May the Chief Shepherd strengthen them, may their family be knit tightly ' ||
      'in love, and may every soul under their watch be brought closer to Christ.',
      target_row.full_name
    );
  end if;

  -- One feed post per promotion, authored by the actor's row for RLS reasons
  -- but flagged as a system post so the byline renders as the church.
  insert into public.posts (author_id, body, status, is_system)
  values (actor_row.id, message, 'approved', true);

  -- Notify the promoted person and every current leader. The actor is not
  -- excluded — a Head Pastor promoting a Leader still gets the announcement
  -- so it appears in their bell like anyone else's.
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, actor_row.id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false
     and (p.id = target_row.id or p.is_leader = true);
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;
