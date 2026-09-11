/**
 * Rules for Daily Bible Verse content.
 *
 * Kept pure and free of database or React imports so it can be tested directly
 * and so the same normalisation is available to any code path that needs it.
 * The database applies the equivalent rules in generated columns and check
 * constraints; these exist so a problem can be caught and explained before it
 * reaches Postgres as a raw constraint violation.
 */

/** Lower case, punctuation stripped, whitespace collapsed. */
export function normalizeReminder(text) {
  return String(text ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Same idea for references, but colons survive because they carry meaning. */
export function normalizeReference(ref) {
  return String(ref ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9: ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function wordCount(text) {
  const trimmed = String(text ?? '').trim();
  return trimmed ? trimmed.split(/\s+/).length : 0;
}

/**
 * Dice coefficient over word bigrams.
 *
 * Chosen over raw character overlap because it catches the failure that
 * actually matters here: a reminder reworded a little, keeping the same phrases
 * in the same order. Postgres uses trigram similarity for the same job at write
 * time; this is the equivalent check available to JavaScript.
 */
export function similarity(a, b) {
  const bigrams = (text) => {
    const words = normalizeReminder(text).split(' ').filter(Boolean);
    const out = new Map();
    for (let i = 0; i < words.length - 1; i++) {
      const key = `${words[i]} ${words[i + 1]}`;
      out.set(key, (out.get(key) || 0) + 1);
    }
    return out;
  };

  const left = bigrams(a);
  const right = bigrams(b);
  const leftTotal = [...left.values()].reduce((n, v) => n + v, 0);
  const rightTotal = [...right.values()].reduce((n, v) => n + v, 0);
  if (!leftTotal || !rightTotal) return normalizeReminder(a) === normalizeReminder(b) ? 1 : 0;

  let shared = 0;
  for (const [key, count] of left) {
    if (right.has(key)) shared += Math.min(count, right.get(key));
  }
  return (2 * shared) / (leftTotal + rightTotal);
}

export const SIMILARITY_LIMIT = 0.55;

export function isTooSimilar(candidate, existing) {
  return existing.some((other) => similarity(candidate, other) > SIMILARITY_LIMIT);
}

/** Books of the Bible, so a fabricated reference can be refused. */
const BOOKS = new Set([
  'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
  '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles','Ezra',
  'Nehemiah','Esther','Job','Psalm','Psalms','Proverbs','Ecclesiastes','Song of Solomon',
  'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
  'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
  'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
  'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
  '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
  '1 John','2 John','3 John','Jude','Revelation',
]);

const REFERENCE = /^((?:[1-3] )?[A-Z][A-Za-z ]*?) (\d{1,3}):(\d{1,3})(?:-(\d{1,3}))?$/;

/** True only for a real book with a plausible chapter and verse. */
export function isValidReference(ref) {
  const match = REFERENCE.exec(String(ref ?? '').trim());
  if (!match) return false;

  const [, book, chapter, start, end] = match;
  if (!BOOKS.has(book)) return false;
  if (Number(chapter) < 1 || Number(start) < 1) return false;
  if (end !== undefined && Number(end) < Number(start)) return false;
  return true;
}

/**
 * Everything the brief forbids in generated content, in one place, so a single
 * call answers whether a pool entry may be stored.
 */
export function validateContent({ reference, reminder }) {
  const problems = [];

  if (!isValidReference(reference)) problems.push('reference is not a real Bible reference');

  const words = wordCount(reminder);
  if (words < 50 || words > 90) problems.push(`reminder is ${words} words, needs 50 to 90`);
  if (/[—–]/.test(reminder)) problems.push('reminder contains an em dash');
  // Anything outside Latin-1 plus curly quotes is an emoji or similar.
  if (/[^\x00-\x7F‘’“”]/.test(reminder)) problems.push('reminder contains an emoji or non-standard character');
  if (/#/.test(reminder)) problems.push('reminder contains a hashtag');

  return { ok: problems.length === 0, problems };
}
