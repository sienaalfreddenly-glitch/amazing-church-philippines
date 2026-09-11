-- Reminders written whole, not assembled from parts.
--
-- The previous generator stitched two template fragments together to reach the
-- fifty word minimum. It produced text like "you did. you do not have to find
-- the right words for it": a lowercase sentence start, because the fragment was
-- written to follow a clause, and two unrelated thoughts with nothing joining
-- them. Hitting a word count is not the same as writing a sentence.
--
-- Each template is now one finished reminder of the right length, in plain
-- language, with the grammar already correct. Generation picks one and stores
-- it against a verse. Nothing is concatenated, so nothing can come out
-- ungrammatical.
--
-- Capacity is templates multiplied by verses rather than pairs multiplied by
-- verses. Sixty templates against 13,239 eligible verses is roughly 794,000
-- reminders, and every template added multiplies that again. Fewer, better
-- reminders is the right trade: a reader meets one a day, and one that reads
-- badly is worse than none.

alter table public.reminder_templates
  add column if not exists text text;

update public.reminder_templates
set text = opening || ' ' || body || ' ' || closing
where text is null;

alter table public.reminder_templates alter column text set not null;

-- The old parts are no longer used for composition.
alter table public.reminder_templates alter column opening drop not null;
alter table public.reminder_templates alter column body    drop not null;
alter table public.reminder_templates alter column closing drop not null;

-- Start again. The rows already here were assembled by the old routine and read
-- badly, so they are cleared before the stricter rules are applied rather than
-- being migrated into a shape they cannot satisfy.
delete from public.daily_assignments;
delete from public.daily_reminders;
delete from public.reminder_templates;

-- A template is now a complete reminder, so it must satisfy the same rules the
-- stored reminder does. Checking here means a badly written template is
-- rejected when it is added rather than discovered by a reader.
alter table public.reminder_templates drop constraint if exists template_length;
alter table public.reminder_templates
  add constraint template_length check (
    text is null
    or array_length(regexp_split_to_array(trim(text), '\s+'), 1) between 50 and 90
  );

alter table public.reminder_templates drop constraint if exists template_starts_capital;
alter table public.reminder_templates
  add constraint template_starts_capital check (text is null or text ~ '^[A-Z]');

alter table public.reminder_templates drop constraint if exists template_ends_stop;
alter table public.reminder_templates
  add constraint template_ends_stop check (text is null or text ~ '[.!?]$');

alter table public.reminder_templates alter column opening set default '';
alter table public.reminder_templates alter column body    set default '';
alter table public.reminder_templates alter column closing set default '';

-- Uniqueness moves to the finished text. The old index hashed the three part
-- columns, which are unused now, so every new template hashed identically and
-- collided with the first one inserted.
drop index if exists reminder_templates_uniq;
create unique index if not exists reminder_templates_text_uniq
  on public.reminder_templates (md5(lower(regexp_replace(text, '\s+', ' ', 'g'))));
