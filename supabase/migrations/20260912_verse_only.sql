-- Drop the reminder from the daily verse.
--
-- The feature is now just the verse. Today's Reminder is gone from the page, so
-- an assignment no longer needs a reminder attached to it.
--
-- The reminder tables, the written library and the generator are left in place
-- rather than dropped. They cost nothing while unused, they hold ninety pieces
-- of writing, and bringing the feature back later is then a matter of showing a
-- column again rather than rebuilding it. Nothing reads them now.

alter table public.daily_assignments alter column reminder_id drop not null;

-- Without a reminder, what stops two people getting the same verse today is
-- nothing: that was deliberate and stays that way. What still holds is one
-- assignment per reader per day, and a reader not seeing the same verse twice
-- until they have seen everything.
create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 20;

      if is_member then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random()
        limit 1;

        -- Seen everything: allow a repeat rather than showing nothing.
        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
        -- Visitors still only meet the welcoming verses, with no fallback to
        -- an untagged one.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1 from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1 from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random() limit 1;
        end if;
      end if;

      exit when v_id is null;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, p_day, 'verse')
      on conflict do nothing
      returning id into made;

      if made is null then
        -- A concurrent request for this same reader won the race; read it back
        -- rather than drawing again.
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v on v.id = a.verse_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

drop function if exists public.my_daily_content();
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    auth.uid(), null, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;

drop function if exists public.visitor_daily_content(uuid);
create or replace function public.visitor_daily_content(p_visitor uuid)
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    null, p_visitor, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.visitor_daily_content(uuid) from public;
grant execute on function public.visitor_daily_content(uuid) to anon, authenticated;
