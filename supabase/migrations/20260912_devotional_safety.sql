-- Restrict which verses can be drawn as a daily reading.
--
-- WHY THIS EXISTS
--
-- Drawing uniformly across all 27,475 verses looks correct and is not. A test
-- run of ten member draws returned Genesis 34:18 and Genesis 19:36, which sit
-- in the accounts of the rape of Dinah and of Lot's daughters. Those are
-- Scripture and they are in the Bible for a reason, but a church website that
-- greets someone with them on a Tuesday morning has done real harm, and no
-- amount of technical correctness makes up for it.
--
-- The earlier heuristic only screened out genealogies, measurements and short
-- fragments. It had no view on narrative content at all.
--
-- WHAT THIS DOES
--
-- Eligibility becomes an allowlist by book rather than a blocklist by phrase. A
-- blocklist has to anticipate every distressing passage, and it will always
-- miss some. An allowlist is wrong only in being conservative, which is the
-- right direction to be wrong in here.
--
-- The pool is still large: the wisdom and prophetic books, the Gospels and the
-- Epistles come to roughly ten thousand verses. Narrative history stays in the
-- database and remains readable elsewhere; it simply is not drawn at random and
-- handed to somebody as their word for the day.
--
-- TO WIDEN IT: add books to devotional_books below, or tag individual verses
-- from any book with a topic, which makes them eligible regardless of book.

create table if not exists public.devotional_books (
  name text primary key references public.bible_books(name)
);

insert into public.devotional_books (name) values
  -- Wisdom and worship
  ('Psalms'), ('Proverbs'), ('Ecclesiastes'),
  -- Prophets, which are largely addressed to the reader
  ('Isaiah'), ('Jeremiah'), ('Lamentations'), ('Hosea'), ('Joel'), ('Amos'),
  ('Obadiah'), ('Jonah'), ('Micah'), ('Nahum'), ('Habakkuk'), ('Zephaniah'),
  ('Haggai'), ('Zechariah'), ('Malachi'),
  -- Gospels
  ('Matthew'), ('Mark'), ('Luke'), ('John'),
  -- Letters, which are written as direct address
  ('Romans'), ('1 Corinthians'), ('2 Corinthians'), ('Galatians'), ('Ephesians'),
  ('Philippians'), ('Colossians'), ('1 Thessalonians'), ('2 Thessalonians'),
  ('1 Timothy'), ('2 Timothy'), ('Titus'), ('Philemon'), ('Hebrews'), ('James'),
  ('1 Peter'), ('2 Peter'), ('1 John'), ('2 John'), ('3 John'), ('Jude')
on conflict (name) do nothing;

-- Recompute eligibility. A verse qualifies if it is in an allowed book and
-- already passed the earlier structural screening, or if it has been
-- deliberately tagged with a topic by a person.
update public.daily_verses v
set devotional = (
  (exists (select 1 from public.devotional_books d where d.name = v.book) and v.devotional)
  or exists (select 1 from public.verse_topics vt where vt.verse_id = v.id)
);

-- Even inside allowed books some passages are graphic or are curses. Screening
-- by content is a blunt instrument and is applied only as a second pass on top
-- of the allowlist, never as the only defence.
update public.daily_verses
set devotional = false
where devotional
  and verse_text ~* '\m(rape|raped|ravish|concubine|slaughter|disembowel|dash(ed)? .{0,20}(pieces|rocks)|rip(ped)? open|bloodshed|harlot|whore|adulteress)\M';

-- Anything very short or very long does not stand alone as a daily reading.
update public.daily_verses
set devotional = false
where devotional
  and (array_length(regexp_split_to_array(trim(verse_text), '\s+'), 1) < 10
       or array_length(regexp_split_to_array(trim(verse_text), '\s+'), 1) > 70);
