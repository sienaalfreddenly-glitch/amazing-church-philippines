import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  normalizeReminder,
  normalizeReference,
  wordCount,
  similarity,
  isTooSimilar,
  isValidReference,
  validateContent,
  SIMILARITY_LIMIT,
} from './daily.js';

test('normalisation lowercases, strips punctuation and collapses spaces', () => {
  assert.equal(
    normalizeReminder('  God IS  good, always!!  '),
    'god is good always',
  );
  // Two reminders differing only in punctuation and case are the same string.
  assert.equal(
    normalizeReminder('You are not alone.'),
    normalizeReminder('you  are, not  alone!'),
  );
});

test('reference normalisation keeps the colon that carries meaning', () => {
  assert.equal(normalizeReference('Psalm 23:1'), 'psalm 23:1');
  assert.equal(normalizeReference('1 John 4:19'), '1 john 4:19');
});

test('word count matches the 50 to 90 rule', () => {
  assert.equal(wordCount(''), 0);
  assert.equal(wordCount('one two   three'), 3);
});

test('an exact duplicate reminder scores as identical', () => {
  const text = 'God is close to you today and he has not forgotten what you are carrying';
  assert.equal(similarity(text, text), 1);
});

test('a lightly edited reminder is caught as too similar', () => {
  const original =
    'You may have spent today feeling like nobody really noticed you but God did and he is not standing at a distance';
  const reworded =
    'You may have spent today feeling like nobody truly noticed you but God did and he is not standing at a distance';

  assert.ok(similarity(original, reworded) > SIMILARITY_LIMIT);
  assert.ok(isTooSimilar(reworded, [original]));
});

test('a genuinely different reminder is accepted', () => {
  const a = 'Waiting is its own kind of work and nobody claps for it, but the time is not wasted';
  const b = 'Your job may feel small and unnoticed, yet the care you put into it still mattered';

  assert.ok(similarity(a, b) < SIMILARITY_LIMIT);
  assert.ok(!isTooSimilar(b, [a]));
});

test('real Bible references are accepted', () => {
  for (const ref of ['Psalm 23:1', '1 John 4:19', 'Romans 8:28', 'Lamentations 3:22-23', 'Revelation 21:4']) {
    assert.ok(isValidReference(ref), `${ref} should be valid`);
  }
});

test('fabricated references are rejected', () => {
  for (const ref of ['Hezekiah 3:16', 'Book of Mormon 1:1', 'Psalm', 'John 3', 'Psalm 0:1', 'Romans 8:10-2']) {
    assert.ok(!isValidReference(ref), `${ref} should be rejected`);
  }
});

test('content validation enforces every writing rule', () => {
  const good = Array.from({ length: 60 }, (_, i) => `word${i}`).join(' ');

  assert.deepEqual(validateContent({ reference: 'Romans 8:28', reminder: good }), {
    ok: true, problems: [],
  });

  const tooShort = validateContent({ reference: 'Romans 8:28', reminder: 'far too short' });
  assert.equal(tooShort.ok, false);
  assert.ok(tooShort.problems.some((p) => p.includes('50 to 90')));

  const emDash = validateContent({ reference: 'Romans 8:28', reminder: `${good} — and more` });
  assert.ok(emDash.problems.some((p) => p.includes('em dash')));

  const emoji = validateContent({ reference: 'Romans 8:28', reminder: `${good} 🙏` });
  assert.ok(emoji.problems.some((p) => p.includes('emoji')));

  const hashtag = validateContent({ reference: 'Romans 8:28', reminder: `${good} #blessed` });
  assert.ok(hashtag.problems.some((p) => p.includes('hashtag')));

  const fakeRef = validateContent({ reference: 'Hezekiah 1:1', reminder: good });
  assert.ok(fakeRef.problems.some((p) => p.includes('reference')));
});

test('the page renders only the two requested sections', () => {
  const source = readFileSync(new URL('../components/DailyVerse.js', import.meta.url), 'utf8');

  assert.ok(source.includes('Daily Bible Verse'));
  assert.ok(source.includes("Today&apos;s Reminder"));

  // The brief forbids these outright.
  assert.ok(!/>\s*Lesson\s*</.test(source), 'a Lesson section must not be rendered');
  assert.ok(!/Short Prayer/.test(source), 'a Short Prayer section must not be rendered');
  assert.ok(!/[—–]/.test(source), 'no em dashes in the component');
  assert.ok(!/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(source), 'no emoji in the component');
});
