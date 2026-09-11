-- Stop counting words.
--
-- The 50 to 90 word rule was mine, not a requirement, and it was doing harm. It
-- rejected four perfectly good reminders for being 44 to 49 words, and earlier
-- it pushed me into stitching two fragments together to pad a reminder up to
-- length, which is what produced the ungrammatical text. A reminder should be
-- as long as the thought needs and no longer.
--
-- The checks that remain are the ones about quality rather than quantity:
-- it must start with a capital, end with proper punctuation, avoid em dashes
-- and emoji, avoid hashtags, avoid assuming who is reading, and not repeat
-- something already written for the same verse.

alter table public.reminder_templates drop constraint if exists template_length;
alter table public.daily_reminders    drop constraint if exists reminder_length;

-- Grammar rules now apply to stored reminders too, not just to templates. A
-- reminder is what somebody actually reads, so it is the thing worth checking.
alter table public.daily_reminders drop constraint if exists reminder_starts_capital;
alter table public.daily_reminders
  add constraint reminder_starts_capital check (reminder ~ '^[A-Z]');

alter table public.daily_reminders drop constraint if exists reminder_ends_stop;
alter table public.daily_reminders
  add constraint reminder_ends_stop check (reminder ~ '[.!?]$');

-- No double spaces, and no lowercase word starting a new sentence, which is the
-- signature of text that was joined together rather than written.
alter table public.daily_reminders drop constraint if exists reminder_clean_spacing;
alter table public.daily_reminders
  add constraint reminder_clean_spacing check (reminder !~ '  ' and reminder !~ '[.!?] +[a-z]');

alter table public.reminder_templates drop constraint if exists template_clean_spacing;
alter table public.reminder_templates
  add constraint template_clean_spacing check (text !~ '  ' and text !~ '[.!?] +[a-z]');
