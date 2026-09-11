/**
 * Import the whole Bible into daily_verses.
 *
 * Source is bible-api.com serving the World English Bible, which is public
 * domain. That matters: the ESV and most modern translations are copyrighted
 * and cannot be bulk stored, whereas the WEB can be redistributed freely.
 *
 * Run with:
 *   node scripts/import-bible.mjs
 *
 * Safe to re-run. Verses are matched on their reference, so an interrupted run
 * simply resumes, and a completed run inserts nothing.
 *
 * Writes SQL to stdout in batches rather than talking to the database itself,
 * so the import needs no database driver and can be piped into psql:
 *   node scripts/import-bible.mjs > /tmp/bible.sql
 */

import { readFileSync } from 'node:fs';
import { BIBLE_BOOKS } from '../src/lib/bible.js';

// Books whose text is mostly names, measurements, census figures or legal
// clauses. Every verse is still imported; these are marked not devotional so
// the daily draw does not open the site on a list of who begat whom.
const NON_DEVOTIONAL_BOOKS = new Set([
  'Leviticus', 'Numbers', '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah',
]);

// Verses that are plainly a list or a fragment rather than a thought.
function looksDevotional(book, text) {
  const words = text.trim().split(/\s+/).length;
  if (words < 8 || words > 80) return false;
  if (NON_DEVOTIONAL_BOOKS.has(book)) return false;
  // Genealogies and census lines.
  if (/\b(begat|became the father of|son of|the sons of)\b/i.test(text) && words < 30) return false;
  if (/\bcubits?\b|\bshekels?\b|\bhomer\b/i.test(text)) return false;
  // Lines that are mostly numerals.
  const digits = (text.match(/\d/g) || []).length;
  if (digits > text.length * 0.05) return false;
  return true;
}

const escape = (s) => s.replace(/'/g, "''");

async function fetchChapter(book, chapter, attempt = 1) {
  const url = `https://bible-api.com/${encodeURIComponent(book)}+${chapter}?translation=web`;
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return Array.isArray(data.verses) ? data.verses : [];
  } catch (err) {
    if (attempt >= 8) {
      process.stderr.write(`SKIPPED ${book} ${chapter}: ${err.message}\n`);
      return [];
    }
    // The API returns 429 under sustained load, so back off hard. A slow
    // complete import beats a fast one with holes in it.
    await new Promise((r) => setTimeout(r, Math.min(30000, 2000 * 2 ** (attempt - 1))));
    return fetchChapter(book, chapter, attempt + 1);
  }
}

// Chapters already present are skipped by the ON CONFLICT below, so an
// interrupted or rate-limited run is completed by running the script again.
// Pass a file of "Book Chapter" lines on argv to restrict a pass to those.
const onlyArg = process.argv[2];
const NEWLINE = String.fromCharCode(10);
const only = onlyArg
  ? new Set(readFileSync(onlyArg, 'utf8').split(NEWLINE).map((l) => l.trim()).filter(Boolean))
  : null;

const total = BIBLE_BOOKS.reduce((n, b) => n + b.chapters, 0);
let done = 0;
let rows = 0;

process.stdout.write('begin;\n');

for (const book of BIBLE_BOOKS) {
  for (let chapter = 1; chapter <= book.chapters; chapter++) {
    if (only && !only.has(`${book.name} ${chapter}`)) continue;
    const verses = await fetchChapter(book.name, chapter);
    done++;
    // Steady pacing between chapters, which avoids most rate limiting.
    await new Promise((r) => setTimeout(r, 400));

    const values = [];
    for (const v of verses) {
      const text = String(v.text || '').replace(/\s+/g, ' ').trim();
      if (!text) continue;
      // Em dashes are forbidden in stored content, and the WEB uses them.
      const clean = text.replace(/[—–]/g, ', ').replace(/\s+,/g, ',').replace(/\s+/g, ' ').trim();
      const reference = `${v.book_name} ${v.chapter}:${v.verse}`;
      values.push(
        `('${escape(reference)}','${escape(clean)}',${looksDevotional(book.name, clean)})`,
      );
    }

    if (values.length) {
      process.stdout.write(
        'insert into daily_verses (reference, verse_text, devotional) values\n'
        + values.join(',\n')
        + '\non conflict (reference_norm) do nothing;\n',
      );
      rows += values.length;
    }

    if (done % 25 === 0) {
      process.stderr.write(`${done}/${total} chapters, ${rows} verses\n`);
    }
  }
}

process.stdout.write('commit;\n');
process.stderr.write(`done: ${done} chapters, ${rows} verses\n`);
