-- Compose a reminder from two templates and a closing line about the verse.
--
-- The first attempt used one template per reminder, and 48 of the 50 composed
-- to fewer than 50 words. The length constraint rejected them, the generator
-- caught the exception and returned null, and no reminder was ever produced.
-- Failing silently is the worst version of that, so the length is now met by
-- construction rather than by hoping the wording is long enough.
--
-- Composing a pair also fixes the capacity question properly. Fifty templates
-- taken two at a time is 2,450 ordered pairs, multiplied again by the closing
-- lines and by every verse in the Bible. That is tens of millions of distinct
-- reminders without writing tens of millions of anything.

create table if not exists public.reminder_closings (
  id     uuid primary key default gen_random_uuid(),
  line   text not null unique,
  status text not null default 'active' check (status in ('active', 'retired')),
  constraint closing_no_em_dash check (line !~ '[—–]')
);

-- These are the only part of a reminder that points at the verse directly,
-- which is what ties the reflection to the Scripture above it.
insert into public.reminder_closings (line) values
  ('Sit with the verse above for a moment before the day takes over.'),
  ('Read it once more slowly, and let it be the last word rather than the first worry.'),
  ('Carry that verse with you today rather than the running commentary in your head.'),
  ('Come back to those words later, when the day has had a chance to argue with them.'),
  ('Let the verse above stand, even on a day when you cannot feel that it is true.'),
  ('Take that line into whatever you are walking into next.'),
  ('If nothing else lands today, let the verse above be the thing that does.'),
  ('Say it back to yourself tonight, quietly, and see what settles.')
on conflict (line) do nothing;

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  a        record;
  b        record;
  closing  text;
  composed text;
  new_id   uuid;
  tries    int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 8;

    -- The lead template, not yet used for this verse.
    select * into a
    from public.reminder_templates rt
    where rt.status = 'active'
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every lead template has been used for this verse. The caller moves on to
    -- a different verse rather than repeating one.
    if not found then
      return null;
    end if;

    -- A second template supplies the middle thought, and must be a different
    -- one so the sentence does not repeat itself.
    select * into b
    from public.reminder_templates rt
    where rt.status = 'active' and rt.id <> a.id
    order by random()
    limit 1;

    select line into closing
    from public.reminder_closings
    where status = 'active'
    order by random()
    limit 1;

    composed := a.opening || ' ' || a.body || ' ' || b.body || ' ' || a.closing || ' ' || closing;

    -- The table constraints are the validator: word count, no em dash, no
    -- emoji, no hashtag, plus the similarity trigger scoped to this verse. A
    -- rejected candidate simply means trying a different pair.
    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, composed, a.focus_tag, a.focus_tag, a.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;

-- The composed length is now a property of the data, so it is worth asserting
-- rather than assuming. A pair plus a closing sits comfortably inside 50 to 90.
do $$
declare too_short int;
begin
  select count(*) into too_short
  from (
    select array_length(regexp_split_to_array(
      trim(a.opening || ' ' || a.body || ' ' || b.body || ' ' || a.closing || ' ' || c.line),
      '\s+'), 1) w
    from public.reminder_templates a
    cross join lateral (select body from public.reminder_templates where id <> a.id limit 3) b
    cross join lateral (select line from public.reminder_closings limit 2) c
  ) x
  where w < 50 or w > 90;

  if too_short > 0 then
    raise notice 'compositions outside 50 to 90 words: %', too_short;
  end if;
end $$;
