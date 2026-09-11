-- Reminders become general, and every verse in the Bible becomes available.
--
-- WHY THIS CHANGES THE ARITHMETIC
--
-- Reminders used to belong to a verse, so the supply of daily content was the
-- number of reminders, and each one was spent for good. That capped the whole
-- feature at a few dozen days.
--
-- A general reminder can sit under any verse. The unit of content is therefore
-- the pairing, not the reminder, and the supply is verses multiplied by
-- reminders. With the whole Bible imported that is 31,102 verses against a few
-- hundred reminders, which is millions of distinct pairings without writing
-- millions of anything.
--
-- WHAT IS STILL GUARANTEED
--
--   A pairing is used once, ever.          unique (verse_id, reminder_id)
--   Nobody reads the same reminder twice.  unique (user_id, reminder_id)
--   No two people share a verse in a day.  unique (assigned_on, verse_id)
--   One assignment per person per day.     unique (user_id, assigned_on)
--
-- The first of those is what you asked for: a verse never carries the same
-- reminder a second time. The second keeps it feeling personal, because no
-- individual ever sees a repeat even though the pool is shared.

-- Reminders no longer belong to a verse.
alter table public.daily_reminders drop column if exists verse_id;

-- A verse needs a flag for whether it works as a daily reading. Genealogies,
-- census lists and legal codes are scripture, but opening the site to a list of
-- names is not what this feature is for. Everything is imported; this decides
-- what the daily draw can pick.
alter table public.daily_verses
  add column if not exists devotional boolean not null default true;

comment on column public.daily_verses.devotional is
  'Eligible for the daily draw. Cleared for verse lists, genealogies and fragments.';

create index if not exists daily_verses_devotional_idx
  on public.daily_verses (devotional) where status = 'active';

-- Rebuild the assignment constraints around the pairing.
alter table public.daily_assignments drop constraint if exists reminder_used_once;
alter table public.daily_assignments drop constraint if exists pairing_used_once;
alter table public.daily_assignments drop constraint if exists reminder_seen_once_per_user;

alter table public.daily_assignments
  add constraint pairing_used_once unique (verse_id, reminder_id);

alter table public.daily_assignments
  add constraint reminder_seen_once_per_user unique (user_id, reminder_id);
