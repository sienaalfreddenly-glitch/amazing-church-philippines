-- Per-reader daily assignment, for members and visitors alike.
--
-- There is no global verse of the day. Two readers may hold the same verse
-- today; what they may never share is a reminder, which is enforced by a unique
-- index on reminder_id rather than by anything in application code.
--
-- Races are handled by writing first and reacting to the conflict, not by
-- checking first and hoping. Every insert is ON CONFLICT DO NOTHING; a lost
-- race returns no row and the loop tries again with a different reminder or a
-- different verse. On the identity conflict the winning row is simply read back.

-- Old signatures return a different row shape, so they are dropped rather than
-- replaced. Postgres refuses to change the return type of an existing function.
drop function if exists public.my_daily_content();
drop function if exists public.visitor_daily_content(uuid);
drop function if exists public.claim_daily_content(uuid, date);

create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  focus_tag     text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  r_id      uuid;
  r_theme   text;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  -- Already assigned today: hand back the same row on every refresh.
  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      if is_member then
        -- Members draw from everything imported that reads as a devotional
        -- thought, and from verses they have not already had where possible.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random()
        limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random()
          limit 1;
        end if;
      else
        -- Visitors only ever meet the welcoming themes. There is deliberately
        -- no fallback to an untagged verse: somebody's first encounter with
        -- this church should not be a random passage from Judges.
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1
            from public.verse_topics vt
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
              select 1
              from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random()
          limit 1;
        end if;
      end if;

      exit when v_id is null;

      -- An unspent reminder for that verse. Reminders are written per verse, so
      -- this is the pool that has to hold out.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.status = 'active'
        and r.verse_id = v_id
        and not exists (
          select 1 from public.daily_assignments a where a.reminder_id = r.id
        )
      order by random()
      limit 1;

      -- No unspent reminder for this verse: make one from a template that has
      -- not been used here before. Returns null once every template has been
      -- used for this verse, in which case try a different verse.
      if r_id is null then
        r_id := public.generate_reminder_for(v_id);
        continue when r_id is null;
        select dr.theme into r_theme from public.daily_reminders dr where dr.id = r_id;
      end if;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, r_id, p_day, coalesce(r_theme, 'general'))
      on conflict do nothing
      returning id into made;

      if made is null then
        -- Either somebody took that reminder, or a concurrent request for this
        -- same reader already created today's row. Check the second case before
        -- drawing again, so a refresh never produces two assignments.
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
  select a.id, v.reference, v.verse_text, r.reminder, r.focus_tag, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

-- Signed-in readers. auth.uid() is taken from the token, so a caller cannot ask
-- for somebody else's assignment.
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid, verse_ref text, verse_text text, reminder text,
  focus_tag text, theme text, assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    auth.uid(), null, (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;

-- Visitors. The id comes from a server-set HttpOnly cookie, never from the page.
create or replace function public.visitor_daily_content(p_visitor uuid)
returns table (
  assignment_id uuid, verse_ref text, verse_text text, reminder text,
  focus_tag text, theme text, assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    null, p_visitor, (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.visitor_daily_content(uuid) from public;
grant execute on function public.visitor_daily_content(uuid) to anon, authenticated;
