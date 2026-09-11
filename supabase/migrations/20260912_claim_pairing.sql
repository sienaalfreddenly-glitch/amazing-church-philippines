-- Claim a verse and a general reminder as a pairing.
--
-- The unit of content is the pairing, so the supply is verses multiplied by
-- reminders rather than the count of either. A reminder is reusable across
-- different verses but never twice under the same verse, and never twice for
-- the same person, which is what keeps it feeling chosen rather than rotated.
create or replace function public.claim_daily_content(p_user uuid, p_day date)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  r_id     uuid;
  r_theme  text;
  attempts int := 0;
  made     uuid;
begin
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      -- A verse that reads as a devotional thought, still free today, and not
      -- one this person has already had.
      select v.id into v_id
      from public.daily_verses v
      where v.status = 'active'
        and v.devotional = true
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.verse_id = v.id
        )
        and not exists (
          select 1 from public.daily_assignments a
          where a.user_id = p_user and a.verse_id = v.id
        )
      -- Random rather than least-recently-used: with tens of thousands of
      -- verses, ordering by last use would sort the entire table on every
      -- request for no benefit anyone can perceive.
      order by random()
      limit 1;

      -- Nothing unseen left for this person; allow a verse they have had
      -- before, since the reminder under it will still be new to them.
      if v_id is null then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and v.devotional = true
          and not exists (
            select 1 from public.daily_assignments a
            where a.assigned_on = p_day and a.verse_id = v.id
          )
        order by random()
        limit 1;
      end if;

      exit when v_id is null;

      -- A reminder never paired with this verse, and never seen by this person.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.status = 'active'
        and not exists (
          select 1 from public.daily_assignments a
          where a.verse_id = v_id and a.reminder_id = r.id
        )
        and not exists (
          select 1 from public.daily_assignments a
          where a.user_id = p_user and a.reminder_id = r.id
        )
      order by random()
      limit 1;

      -- This verse has no reminder left that works for this reader. Try a
      -- different verse rather than giving up.
      continue when r_id is null;

      insert into public.daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, v_id, r_id, p_day, r_theme)
      on conflict do nothing
      returning id into made;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, r.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;
