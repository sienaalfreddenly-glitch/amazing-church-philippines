-- Generating reminders per verse, and scoping duplicate checks to the verse.
--
-- WHY UNIQUENESS MOVES FROM GLOBAL TO PER VERSE
--
-- A reminder belongs to one verse now. A template composed under Psalm 23 and
-- the same template composed under Romans 8 are different reminders, because
-- the verse they sit beneath is what gives them their meaning. A global
-- uniqueness rule would let each template be used exactly once in the entire
-- Bible, which caps the pool at the number of templates.
--
-- Scoped to the verse, 50 templates against roughly 15,000 devotional verses is
-- about 750,000 reminders, and adding templates multiplies that rather than
-- adding to it. Duplicate protection is not weakened: within any one verse, no
-- two reminders may be identical or near identical, which is the comparison
-- that actually matters to a reader.

drop index if exists daily_reminders_norm_uniq;
create unique index if not exists daily_reminders_verse_norm_uniq
  on public.daily_reminders (verse_id, reminder_norm);

-- The near-duplicate guard, now comparing within the verse. It still reads
-- new.reminder directly rather than the generated column, because a stored
-- generated column is not populated until after a before-insert trigger runs.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  candidate_norm text;
  clash record;
begin
  candidate_norm := trim(regexp_replace(
    regexp_replace(lower(new.reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));

  select id, similarity(reminder_norm, candidate_norm) as score
    into clash
  from public.daily_reminders
  where id <> new.id
    and verse_id = new.verse_id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to an existing reminder for this verse (%)',
      round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Generation
--
-- WHEN IT RUNS: during assignment, on demand, for one verse at a time. Not in a
-- background job, because the pool is enormous and pre-generating it would mean
-- writing three quarters of a million rows nobody may ever read. Not before
-- assignment either, because which verse a reader gets is not known until then.
--
-- The generator makes at most one reminder per call and the claim loop is
-- bounded, so a single request can never trigger unbounded generation.
-- ---------------------------------------------------------------------------

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  t          record;
  composed   text;
  new_id     uuid;
  tries      int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 5;

    -- A template not yet used for this verse.
    select * into t
    from public.reminder_templates rt
    where rt.status = 'active'
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every template already used for this verse.
    if not found then
      return null;
    end if;

    composed := t.opening || ' ' || t.body || ' ' || t.closing;

    -- The constraints on daily_reminders do the validating: word count, no em
    -- dash, no emoji, no hashtag, and the similarity trigger above. A candidate
    -- that fails any of them raises, and the loop tries another template rather
    -- than storing something invalid.
    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, composed, t.focus_tag, t.focus_tag, t.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
    -- Lost a race, or the candidate was rejected. Try a different template.
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;
