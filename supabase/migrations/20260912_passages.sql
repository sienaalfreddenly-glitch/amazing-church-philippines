-- Show a passage, not a stranded verse.
--
-- Verse divisions were added centuries after the text was written and they cut
-- across sentences constantly. Isaiah 38:2 ends on a comma; on its own it reads
-- as a fragment. Drawing a single verse was giving people half a thought.
--
-- HOW THE BOUNDARIES ARE FOUND
--
-- A passage is a run of verses inside one chapter that begins after a sentence
-- ends and finishes where one ends. From the drawn verse it walks backwards
-- while the preceding verse does not close a sentence, then forwards until one
-- closes, then keeps going to a minimum length so there is some context rather
-- than a lone line, always stopping on a sentence end.
--
-- It is a heuristic over punctuation rather than real paragraph data, because
-- the imported text has no paragraph markers. It gets the common cases right
-- and errs towards including a little more, which is the safer direction.

-- The World English Bible uses curly quotation marks, so a sentence can end
-- with a full stop followed by one or two closing quotes.
create or replace function public.ends_sentence(t text)
returns boolean
language sql
immutable
as $$
  select trim(coalesce(t, '')) ~ '[.!?]["''’”]{0,2}$';
$$;

create or replace function public.passage_for(p_verse uuid)
returns table (reference text, passage_text text, first_verse smallint, last_verse smallint)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  anchor    record;
  first_v   smallint;
  last_v    smallint;
  max_v     smallint;
  guard     int := 0;
  prev_text text;
  last_text text;
  body      text;
  words     int;
begin
  select v.book, v.chapter, v.verse, v.verse_text
    into anchor
  from public.daily_verses v where v.id = p_verse;

  if not found then
    return;
  end if;

  select max(v.verse) into max_v
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter;

  first_v := anchor.verse;
  last_v  := anchor.verse;

  -- Backwards: if the verse before this one does not close a sentence, this
  -- verse is a continuation and the thought started earlier.
  loop
    guard := guard + 1;
    exit when guard > 6 or first_v <= 1;

    select v.verse_text into prev_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = first_v - 1;

    exit when prev_text is null or public.ends_sentence(prev_text);
    first_v := first_v - 1;
  end loop;

  -- Forwards: keep going until a verse closes a sentence, then keep going a
  -- little further so the passage has some shape rather than stopping at the
  -- first full stop.
  guard := 0;
  loop
    guard := guard + 1;
    exit when guard > 8 or last_v >= max_v;

    select v.verse_text into last_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = last_v;

    select coalesce(sum(array_length(regexp_split_to_array(trim(v.verse_text), '\s+'), 1)), 0)
      into words
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter
      and v.verse between first_v and last_v;

    -- Long enough and ending cleanly: stop here.
    exit when public.ends_sentence(last_text)
          and (last_v - first_v + 1) >= 3
          and words >= 45;

    -- Never run away with it, even mid-sentence.
    exit when words > 170 or (last_v - first_v + 1) >= 8;

    last_v := last_v + 1;
  end loop;

  select string_agg(v.verse_text, ' ' order by v.verse)
    into body
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter
    and v.verse between first_v and last_v;

  return query select
    anchor.book || ' ' || anchor.chapter || ':' || first_v
      || case when last_v > first_v then '-' || last_v else '' end,
    body,
    first_v,
    last_v;
end;
$$;

revoke all on function public.passage_for(uuid) from public;
grant execute on function public.passage_for(uuid) to authenticated, anon;

-- The daily draw returns the passage rather than the single verse it landed on.
-- The verse still decides what is drawn; the passage is how it is shown.
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
        order by random() limit 1;

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
        order by random() limit 1;

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
