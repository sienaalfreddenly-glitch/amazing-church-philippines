-- Restore passage expansion for the daily verse.
--
-- 20260912_verse_only.sql redefined claim_daily_for to return the raw single
-- verse from daily_verses, bypassing passage_for(). That put stranded verses
-- like Mark 11:5 back on the page. This rebuilds claim_daily_for identically
-- except the final return joins passage_for(), same as 20260912_passages.sql.

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

        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
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
  select a.id, p.reference, p.passage_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  cross join lateral public.passage_for(a.verse_id) p
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;
