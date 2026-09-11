-- Canonical book order and testament.
--
-- Stored rather than derived so verses can be listed in Bible order without the
-- application knowing the sequence, and so a query can filter by testament
-- without a list of names in the WHERE clause.
--
-- The names match what the import writes, which is bible-api.com's spelling.
-- Note Psalms rather than Psalm: the API uses the plural, and mixing the two
-- silently splits the book in two.

create table if not exists public.bible_books (
  name       text primary key,
  book_order smallint not null unique,
  testament  text not null check (testament in ('OT', 'NT')),
  chapters   smallint not null
);

insert into public.bible_books (name, book_order, testament, chapters) values
('Genesis',1,'OT',50),('Exodus',2,'OT',40),('Leviticus',3,'OT',27),('Numbers',4,'OT',36),
('Deuteronomy',5,'OT',34),('Joshua',6,'OT',24),('Judges',7,'OT',21),('Ruth',8,'OT',4),
('1 Samuel',9,'OT',31),('2 Samuel',10,'OT',24),('1 Kings',11,'OT',22),('2 Kings',12,'OT',25),
('1 Chronicles',13,'OT',29),('2 Chronicles',14,'OT',36),('Ezra',15,'OT',10),('Nehemiah',16,'OT',13),
('Esther',17,'OT',10),('Job',18,'OT',42),('Psalms',19,'OT',150),('Proverbs',20,'OT',31),
('Ecclesiastes',21,'OT',12),('Song of Solomon',22,'OT',8),('Isaiah',23,'OT',66),('Jeremiah',24,'OT',52),
('Lamentations',25,'OT',5),('Ezekiel',26,'OT',48),('Daniel',27,'OT',12),('Hosea',28,'OT',14),
('Joel',29,'OT',3),('Amos',30,'OT',9),('Obadiah',31,'OT',1),('Jonah',32,'OT',4),
('Micah',33,'OT',7),('Nahum',34,'OT',3),('Habakkuk',35,'OT',3),('Zephaniah',36,'OT',3),
('Haggai',37,'OT',2),('Zechariah',38,'OT',14),('Malachi',39,'OT',4),
('Matthew',40,'NT',28),('Mark',41,'NT',16),('Luke',42,'NT',24),('John',43,'NT',21),
('Acts',44,'NT',28),('Romans',45,'NT',16),('1 Corinthians',46,'NT',16),('2 Corinthians',47,'NT',13),
('Galatians',48,'NT',6),('Ephesians',49,'NT',6),('Philippians',50,'NT',4),('Colossians',51,'NT',4),
('1 Thessalonians',52,'NT',5),('2 Thessalonians',53,'NT',3),('1 Timothy',54,'NT',6),('2 Timothy',55,'NT',4),
('Titus',56,'NT',3),('Philemon',57,'NT',1),('Hebrews',58,'NT',13),('James',59,'NT',5),
('1 Peter',60,'NT',5),('2 Peter',61,'NT',3),('1 John',62,'NT',5),('2 John',63,'NT',1),
('3 John',64,'NT',1),('Jude',65,'NT',1),('Revelation',66,'NT',22)
on conflict (name) do nothing;

update public.daily_verses v
set book_order = b.book_order, testament = b.testament
from public.bible_books b
where b.name = v.book and (v.book_order is null or v.testament is null);

-- Only the 66 canonical books may be stored, checked against the table rather
-- than against a regular expression that would accept Hezekiah.
alter table public.daily_verses drop constraint if exists verse_book_is_canonical;
alter table public.daily_verses
  add constraint verse_book_is_canonical
  foreign key (book) references public.bible_books(name);
