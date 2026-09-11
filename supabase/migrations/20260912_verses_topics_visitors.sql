-- Daily verse: per-reader randomisation, verse topics, visitor mode.
--
-- WHAT CHANGES AND WHY
--
-- 1. There is no global verse of the day any more. The unique index on
--    (assigned_on, verse_id) is dropped, so two people may hold the same verse
--    on the same day. What they may never share is a reminder.
--
-- 2. Visitors get an assignment too, identified by a server-generated id in an
--    HttpOnly cookie rather than by anything the browser can choose for itself.
--    Exactly one of user_id and visitor_id is set, enforced by a check.
--
-- 3. Verses carry structured fields (book, book_order, chapter, verse,
--    testament) so they can be ordered, filtered and joined to topics.
--
-- 4. Topics are a normalised join table. Visitors only ever see verses tagged
--    with the welcoming topics, and never fall back to an untagged verse.
--
-- ON SCRIPTURE TEXT
--
-- The stored text is the World English Bible, which is public domain. The ESV
-- is copyrighted by Crossway and its API is licensed for displaying passages,
-- not for reproducing the translation, which is why it caps a query at 500
-- verses. Storing all 31,102 ESV verses would be a copy of the whole work, so
-- the corpus stays WEB and ESV wording is fetched live for the single verse a
-- reader is shown. See docs/DAILY-VERSE.md.

-- ---------------------------------------------------------------------------
-- 1. Structured verse fields
-- ---------------------------------------------------------------------------

alter table public.daily_verses
  add column if not exists book       text,
  add column if not exists book_order smallint,
  add column if not exists chapter    smallint,
  add column if not exists verse      smallint,
  add column if not exists testament  text check (testament in ('OT', 'NT')),
  add column if not exists updated_at timestamptz not null default now();

-- Backfill from the reference already stored, e.g. "1 John 4:19".
update public.daily_verses
set book    = substring(reference from '^(.*?) [0-9]+:[0-9]+'),
    chapter = (substring(reference from ' ([0-9]+):[0-9]+'))::smallint,
    verse   = (substring(reference from ':([0-9]+)'))::smallint
where book is null and reference ~ '^.+ [0-9]+:[0-9]+';

create unique index if not exists daily_verses_bcv_uniq
  on public.daily_verses (book, chapter, verse)
  where book is not null;

create index if not exists daily_verses_order_idx
  on public.daily_verses (book_order, chapter, verse);

-- ---------------------------------------------------------------------------
-- 2. Topics
--
-- A normalised join table rather than an array column: a verse belongs to
-- several topics, topics are queried by name, and the set will grow. An array
-- would need a GIN index and string matching to do the same job less clearly.
-- ---------------------------------------------------------------------------

create table if not exists public.verse_topic_kinds (
  slug        text primary key,
  label       text not null,
  -- Whether a verse carrying this topic may be shown to somebody who has not
  -- signed up. These are the welcoming themes only.
  visitor_safe boolean not null default false
);

insert into public.verse_topic_kinds (slug, label, visitor_safe) values
  ('love',            'Loved by God',        true),
  ('acceptance',      'Accepted',            true),
  ('identity',        'Identity in Christ',  true),
  ('grace',           'Grace',               true),
  ('adoption',        'Adopted',             true),
  ('no-condemnation', 'No condemnation',     true),
  ('worth',           'Valued',              true),
  ('welcome',         'Welcomed',            true),
  ('belonging',       'Belonging',           true),
  ('cherished',       'Cherished',           true),
  ('mercy',           'Mercy',               true),
  ('reconciliation',  'Reconciled',          true),
  ('comfort',         'Comfort',             false),
  ('courage',         'Courage',             false),
  ('patience',        'Patience',            false),
  ('wisdom',          'Wisdom',              false)
on conflict (slug) do nothing;

create table if not exists public.verse_topics (
  verse_id uuid not null references public.daily_verses(id) on delete cascade,
  topic    text not null references public.verse_topic_kinds(slug) on delete cascade,
  primary key (verse_id, topic)
);

create index if not exists verse_topics_topic_idx on public.verse_topics (topic);

-- ---------------------------------------------------------------------------
-- 3. Reminders belong to a verse again, and carry a focus tag
--
-- The previous model made reminders general and shared across verses. This
-- returns them to a single verse, which is what allows a verse to accumulate
-- thousands of reminders over time through generation.
-- ---------------------------------------------------------------------------

alter table public.daily_reminders
  add column if not exists verse_id   uuid references public.daily_verses(id) on delete cascade,
  add column if not exists focus_tag  text,
  add column if not exists template_id uuid,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists daily_reminders_verse_unused_idx
  on public.daily_reminders (verse_id) where status = 'active';

-- ---------------------------------------------------------------------------
-- 4. Assignments: per reader, not per day globally
-- ---------------------------------------------------------------------------

alter table public.daily_assignments
  add column if not exists visitor_id uuid;

alter table public.daily_assignments alter column user_id drop not null;

-- No global verse of the day. Two people may hold the same verse today.
alter table public.daily_assignments drop constraint if exists one_verse_per_day;
alter table public.daily_assignments drop constraint if exists one_per_user_per_day;
alter table public.daily_assignments drop constraint if exists pairing_used_once;
alter table public.daily_assignments drop constraint if exists reminder_seen_once_per_user;
alter table public.daily_assignments drop constraint if exists reminder_used_once;

-- Exactly one identity per assignment.
alter table public.daily_assignments drop constraint if exists one_identity;
alter table public.daily_assignments
  add constraint one_identity check (
    (user_id is not null and visitor_id is null)
    or (user_id is null and visitor_id is not null)
  );

-- Partial uniques, because one of the two columns is always null.
create unique index if not exists assignments_user_day_uniq
  on public.daily_assignments (user_id, assigned_on) where user_id is not null;

create unique index if not exists assignments_visitor_day_uniq
  on public.daily_assignments (visitor_id, assigned_on) where visitor_id is not null;

-- A reminder is spent permanently, whoever spent it.
create unique index if not exists assignments_reminder_uniq
  on public.daily_assignments (reminder_id);
