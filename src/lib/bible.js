// Bible structure — 66 books with chapter counts.
// Used for deterministic passage picking + a full-Bible reader.

export const OLD_TESTAMENT = [
  { name: 'Genesis',        chapters: 50 }, { name: 'Exodus',         chapters: 40 },
  { name: 'Leviticus',      chapters: 27 }, { name: 'Numbers',        chapters: 36 },
  { name: 'Deuteronomy',    chapters: 34 }, { name: 'Joshua',         chapters: 24 },
  { name: 'Judges',         chapters: 21 }, { name: 'Ruth',           chapters:  4 },
  { name: '1 Samuel',       chapters: 31 }, { name: '2 Samuel',       chapters: 24 },
  { name: '1 Kings',        chapters: 22 }, { name: '2 Kings',        chapters: 25 },
  { name: '1 Chronicles',   chapters: 29 }, { name: '2 Chronicles',   chapters: 36 },
  { name: 'Ezra',           chapters: 10 }, { name: 'Nehemiah',       chapters: 13 },
  { name: 'Esther',         chapters: 10 }, { name: 'Job',            chapters: 42 },
  { name: 'Psalms',         chapters: 150 }, { name: 'Proverbs',       chapters: 31 },
  { name: 'Ecclesiastes',   chapters: 12 }, { name: 'Song of Solomon',chapters:  8 },
  { name: 'Isaiah',         chapters: 66 }, { name: 'Jeremiah',       chapters: 52 },
  { name: 'Lamentations',   chapters:  5 }, { name: 'Ezekiel',        chapters: 48 },
  { name: 'Daniel',         chapters: 12 }, { name: 'Hosea',          chapters: 14 },
  { name: 'Joel',           chapters:  3 }, { name: 'Amos',           chapters:  9 },
  { name: 'Obadiah',        chapters:  1 }, { name: 'Jonah',          chapters:  4 },
  { name: 'Micah',          chapters:  7 }, { name: 'Nahum',          chapters:  3 },
  { name: 'Habakkuk',       chapters:  3 }, { name: 'Zephaniah',      chapters:  3 },
  { name: 'Haggai',         chapters:  2 }, { name: 'Zechariah',      chapters: 14 },
  { name: 'Malachi',        chapters:  4 },
];

export const NEW_TESTAMENT = [
  { name: 'Matthew',          chapters: 28 }, { name: 'Mark',             chapters: 16 },
  { name: 'Luke',             chapters: 24 }, { name: 'John',             chapters: 21 },
  { name: 'Acts',             chapters: 28 }, { name: 'Romans',           chapters: 16 },
  { name: '1 Corinthians',    chapters: 16 }, { name: '2 Corinthians',    chapters: 13 },
  { name: 'Galatians',        chapters:  6 }, { name: 'Ephesians',        chapters:  6 },
  { name: 'Philippians',      chapters:  4 }, { name: 'Colossians',       chapters:  4 },
  { name: '1 Thessalonians',  chapters:  5 }, { name: '2 Thessalonians',  chapters:  3 },
  { name: '1 Timothy',        chapters:  6 }, { name: '2 Timothy',        chapters:  4 },
  { name: 'Titus',            chapters:  3 }, { name: 'Philemon',         chapters:  1 },
  { name: 'Hebrews',          chapters: 13 }, { name: 'James',            chapters:  5 },
  { name: '1 Peter',          chapters:  5 }, { name: '2 Peter',          chapters:  3 },
  { name: '1 John',           chapters:  5 }, { name: '2 John',           chapters:  1 },
  { name: '3 John',           chapters:  1 }, { name: 'Jude',             chapters:  1 },
  { name: 'Revelation',       chapters: 22 },
];

export const BIBLE_BOOKS = [...OLD_TESTAMENT, ...NEW_TESTAMENT];

// Deterministic FNV-1a hash → non-negative 32-bit int
export function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

// Passage length: number of consecutive verses to include.
const PASSAGE_LEN = 4;

export function pickPassage(seed) {
  const book = BIBLE_BOOKS[hash(seed + ':book') % BIBLE_BOOKS.length];
  const chapter = (hash(seed + ':chapter') % book.chapters) + 1;
  // We don't hardcode verse counts; APIs trim if we ask past the end.
  const startVerse = (hash(seed + ':verse') % 25) + 1;
  const endVerse = startVerse + PASSAGE_LEN - 1;
  return { book: book.name, chapter, startVerse, endVerse };
}

// -------- Providers --------

async function fetchWEB({ book, chapter, startVerse, endVerse }) {
  const url = `https://bible-api.com/${encodeURIComponent(book)}+${chapter}:${startVerse}-${endVerse}?translation=web`;
  const res = await fetch(url, { next: { revalidate: 86400 } });
  if (!res.ok) return null;
  const data = await res.json();
  const verses = Array.isArray(data.verses) ? data.verses : [];
  if (!verses.length) return null;
  const text = verses.map(v => v.text.trim()).join(' ');
  const first = verses[0], last = verses[verses.length - 1];
  const ref = first.verse === last.verse
    ? `${first.book_name} ${first.chapter}:${first.verse}`
    : `${first.book_name} ${first.chapter}:${first.verse}-${last.verse}`;
  return { reference: ref, text, translation: '' }; // empty = don't show tag
}

async function fetchESV({ book, chapter, startVerse, endVerse }) {
  const key = process.env.ESV_API_KEY;
  if (!key) return null;
  const q = `${book} ${chapter}:${startVerse}-${endVerse}`;
  const params = new URLSearchParams({
    q,
    'include-headings': 'false',
    'include-footnotes': 'false',
    'include-verse-numbers': 'false',
    'include-short-copyright': 'false',
    'include-passage-references': 'false',
    'include-first-verse-numbers': 'false',
  });
  const res = await fetch(`https://api.esv.org/v3/passage/text/?${params}`, {
    headers: { Authorization: `Token ${key}` },
    next: { revalidate: 86400 },
  });
  if (!res.ok) return null;
  const data = await res.json();
  const text = (data.passages?.[0] || '').trim().replace(/\s+/g, ' ');
  const ref = data.canonical || q;
  if (!text) return null;
  return { reference: ref, text, translation: 'ESV' };
}

export async function fetchDailyVerse(seed) {
  const passage = pickPassage(seed);
  // Prefer ESV if the key is set; otherwise use WEB (no translation tag shown).
  return (await fetchESV(passage)) || (await fetchWEB(passage));
}
