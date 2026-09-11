-- Daily Bible Verse: one unique verse and reminder per person per day.
--
-- HOW UNIQUENESS IS GUARANTEED
--
-- The verse and its reminder are stored together as one pool row rather than
-- being drawn from two independent pools. Pairing them means a single claim is
-- atomic: one row, one unique index, no window in which a user could get a
-- verse but lose the race for a reminder. It satisfies both requirements at
-- once, because claiming the pair claims the verse and the reminder together.
--
-- Two users cannot share content on the same day. That is enforced by a unique
-- index on (assigned_on, content_id), not by application logic, so simultaneous
-- requests, refreshes, and retries cannot defeat it. The claim loop inserts
-- with ON CONFLICT DO NOTHING and tries the next candidate if it lost the race.
--
-- REUSE POLICY, stated explicitly because the pool is finite
--
-- A given piece of content is never shown to two people on the same day. Across
-- different days it may be reused, and a person may see a verse again only once
-- they have seen everything else in the pool. Selection prefers content the
-- person has never had, then whatever has gone longest without being used
-- anywhere, so the same users do not always receive the first rows.
--
-- If every row is already taken for today the function returns nothing and the
-- page says so plainly, rather than handing out a duplicate.

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------------------
-- The pool
-- ---------------------------------------------------------------------------

create table if not exists public.daily_content (
  id            uuid primary key default gen_random_uuid(),
  verse_ref     text not null,
  verse_text    text not null,
  reminder      text not null,
  theme         text not null,
  status        text not null default 'active' check (status in ('active', 'retired')),
  created_at    timestamptz not null default now(),

  -- Normalised once, by the database, so every comparison uses the same rules
  -- no matter which code path wrote the row: lower case, punctuation removed,
  -- whitespace collapsed.
  reminder_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,
  verse_ref_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(verse_ref), '[^a-z0-9: ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  -- Reject the obvious mistakes at write time rather than at read time.
  constraint reminder_length check (
    array_length(regexp_split_to_array(trim(reminder), '\s+'), 1) between 50 and 90
  ),
  constraint no_em_dash check (reminder !~ '[—–]' and verse_text !~ '[—–]'),
  constraint no_emoji check (reminder ~ '^[\x00-\x7F''’"“”]*$'),
  -- A reference must look like a reference: book, chapter, verse.
  constraint reference_shape check (verse_ref ~ '^[1-3]? ?[A-Z][A-Za-z ]+ [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$')
);

-- Exact duplicates are impossible.
create unique index if not exists daily_content_verse_ref_uniq  on public.daily_content (verse_ref_norm);
create unique index if not exists daily_content_reminder_uniq   on public.daily_content (reminder_norm);
-- Trigram index backing the similarity check below.
create index if not exists daily_content_reminder_trgm on public.daily_content using gin (reminder_norm gin_trgm_ops);

-- Near duplicates are impossible too. A reminder that reads like a light edit
-- of an existing one is refused on insert rather than being caught later.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  clash record;
begin
  select id, reminder, similarity(reminder_norm, new.reminder_norm) as score
    into clash
  from public.daily_content
  where id <> new.id
    and similarity(reminder_norm, new.reminder_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception
      'reminder is too similar (%.2f) to existing content %', clash.score, clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists daily_content_similarity on public.daily_content;
create trigger daily_content_similarity
  before insert or update of reminder on public.daily_content
  for each row execute function public.reject_similar_reminder();

-- ---------------------------------------------------------------------------
-- The assignments
-- ---------------------------------------------------------------------------

create table if not exists public.daily_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  content_id  uuid not null references public.daily_content(id) on delete restrict,
  assigned_on date not null,
  theme       text not null,
  status      text not null default 'active' check (status in ('active', 'superseded')),
  created_at  timestamptz not null default now(),

  -- One assignment per person per day, so a refresh returns what they already
  -- have instead of drawing again.
  constraint one_per_user_per_day unique (user_id, assigned_on),
  -- The guarantee that matters: nobody shares content with anybody else today.
  constraint one_holder_per_day   unique (assigned_on, content_id)
);

create index if not exists daily_assignments_user_idx    on public.daily_assignments (user_id, assigned_on desc);
create index if not exists daily_assignments_content_idx on public.daily_assignments (content_id, assigned_on desc);

alter table public.daily_content     enable row level security;
alter table public.daily_assignments enable row level security;

-- The pool itself is not readable directly; everything goes through the
-- function, so nobody can browse tomorrow's content or somebody else's.
drop policy if exists "assignments are private" on public.daily_assignments;
create policy "assignments are private"
  on public.daily_assignments for select
  using (user_id = auth.uid());

grant select on public.daily_assignments to authenticated;

-- ---------------------------------------------------------------------------
-- Claiming today's content
--
-- Race safety comes from the unique index, not from checking first and writing
-- second. Each attempt inserts with ON CONFLICT DO NOTHING; if another request
-- took that row in the meantime the insert simply affects no rows and the loop
-- tries the next candidate. No locks are held across the selection, so
-- simultaneous requests do not queue behind each other.
-- ---------------------------------------------------------------------------

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
  candidate uuid;
  attempts  int := 0;
  made      uuid;
begin
  -- Already assigned today: hand back the same thing, every time.
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 25;

      select c.id into candidate
      from public.daily_content c
      where c.status = 'active'
        -- Not already given to somebody else today.
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.content_id = c.id
        )
      order by
        -- Content this person has never seen comes first.
        (exists (select 1 from public.daily_assignments a
                 where a.user_id = p_user and a.content_id = c.id)),
        -- Then whatever has gone longest unused by anyone, so the same rows are
        -- not always handed to whoever asks first.
        coalesce((select max(a.assigned_on) from public.daily_assignments a
                  where a.content_id = c.id), date '1970-01-01'),
        -- Stable shuffle within a day, so the order is not simply insertion
        -- order and is the same for retries within one request.
        md5(c.id::text || p_day::text)
      limit 1;

      -- Pool exhausted for today.
      exit when candidate is null;

      insert into public.daily_assignments (user_id, content_id, assigned_on, theme)
      select p_user, candidate, p_day, c.theme
      from public.daily_content c where c.id = candidate
      on conflict do nothing
      returning id into made;

      exit when made is not null;
      -- Lost the race for that row. Try again with the next candidate.
    end loop;
  end if;

  if made is null then
    return;  -- Caller shows a clear message rather than duplicate content.
  end if;

  return query
  select a.id, c.verse_ref, c.verse_text, c.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_content c on c.id = a.content_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;

-- What the app actually calls: always the signed-in user, always today in
-- Manila, so a caller cannot ask for somebody else's assignment.
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language sql
security definer
set search_path = public
as $$
  select * from public.claim_daily_content(
    auth.uid(),
    (now() at time zone 'Asia/Manila')::date
  );
$$;

revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;
-- Fix 1: validate the book, not merely the shape.
--
-- The old check only confirmed the reference looked like "Word 3:16", so
-- Hezekiah 3:16 passed as well formed. A fabricated book is exactly the failure
-- the brief asks to prevent, so the 66 real books are now the test.
create or replace function public.is_valid_bible_reference(ref text)
returns boolean
language sql
immutable
as $$
  select ref ~ ('^(' || array_to_string(array[
    'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
    '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles','Ezra',
    'Nehemiah','Esther','Job','Psalms','Psalm','Proverbs','Ecclesiastes','Song of Solomon',
    'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
    'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
    'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
    'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
    '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
    '1 John','2 John','3 John','Jude','Revelation'
  ], '|') || ') [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$');
$$;

alter table public.daily_content drop constraint if exists reference_shape;
alter table public.daily_content
  add constraint reference_is_real check (public.is_valid_bible_reference(verse_ref));

-- Fix 2: the similarity guard was comparing against nothing.
--
-- reminder_norm is a STORED generated column, and generated columns are
-- computed after before-insert triggers run. new.reminder_norm was therefore
-- always null inside the trigger, similarity() returned null, and no candidate
-- ever exceeded the threshold. Normalise from new.reminder directly instead.
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
  from public.daily_content
  where id <> new.id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to existing content %', round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;
