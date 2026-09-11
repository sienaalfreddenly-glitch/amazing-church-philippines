/**
 * Background job: top up the pool of reminders awaiting review.
 *
 * Run it on a schedule, or by hand:
 *   node scripts/generate-reminders.mjs --count 20
 *
 * Options:
 *   --count N   how many to try to write this run (default 20)
 *   --dry-run   write nothing, just print what would be produced
 *
 * Everything it produces lands as 'pending'. Nothing reaches a reader until a
 * leader approves it at /admin/reminders. With no GEMINI_API_KEY the job exits
 * immediately and says so; the hand-written library carries on serving.
 *
 * Requires GEMINI_API_KEY and the Supabase service role key, both from
 * deploy/.env. The service role is needed because this runs outside a request
 * and has no signed-in user behind it.
 */

import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { generateReminder, isGenerationAvailable } from '../src/lib/reminder-generator.js';

// Load deploy/.env without adding a dependency for it.
function loadEnv(path) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return;
  }
  for (const line of text.split(/\r?\n/)) {
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2];
  }
}

loadEnv('deploy/.env');
loadEnv('.env.local');

const args = process.argv.slice(2);
const count = Number(args[args.indexOf('--count') + 1]) || 20;
const dryRun = args.includes('--dry-run');

// Pace requests so a free-tier quota is not burned in one burst.
const DELAY_MS = Number(process.env.GEMINI_DELAY_MS || 3000);

if (!isGenerationAvailable()) {
  console.log('GEMINI_API_KEY is not set. Nothing to do.');
  console.log('The hand-written library keeps serving; this job is optional.');
  process.exit(0);
}

const url = process.env.SUPABASE_INTERNAL_URL
  || process.env.NEXT_PUBLIC_SUPABASE_URL
  || 'http://127.0.0.1:54321';
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!serviceKey) {
  console.error('SUPABASE_SERVICE_ROLE_KEY is required. Check deploy/.env.');
  process.exit(1);
}

const db = createClient(url, serviceKey, { auth: { persistSession: false } });

/**
 * Verses worth writing for: eligible for the daily draw, and holding the fewest
 * approved reminders. Spreading coverage matters more than depth, because a
 * verse with nothing approved is one the draw has to skip.
 */
async function pickVerses(n) {
  const { data, error } = await db.rpc('verses_needing_reminders', { p_limit: n });
  if (error) throw new Error(`could not pick verses: ${error.message}`);
  return data || [];
}

const results = { written: 0, rejected: 0, failed: 0, rateLimited: 0 };

console.log(`Writing up to ${count} reminders${dryRun ? ' (dry run)' : ''}.`);

const verses = await pickVerses(count);
if (!verses.length) {
  console.log('No verses need reminders right now.');
  process.exit(0);
}

for (const verse of verses) {
  const outcome = await generateReminder({
    reference: verse.reference,
    verseText: verse.verse_text,
  });

  if (!outcome.ok) {
    if (outcome.retryable) {
      results.rateLimited++;
      console.log(`  rate limited on ${verse.reference}, stopping early`);
      break;
    }
    // A candidate refused for a rule is a rejection; anything else is a failure.
    const isRule = !/^(network|HTTP|response|no candidate|finished)/.test(outcome.reason);
    if (isRule) results.rejected++; else results.failed++;
    console.log(`  skipped ${verse.reference}: ${outcome.reason}`);
    await new Promise((r) => setTimeout(r, DELAY_MS));
    continue;
  }

  if (dryRun) {
    console.log(`\n  ${verse.reference}\n  ${outcome.text}\n`);
    results.written++;
  } else {
    const { error } = await db.from('daily_reminders').insert({
      verse_id: verse.id,
      reminder: outcome.text,
      theme: 'generated',
      focus_tag: 'generated',
      status: 'pending',
      source: 'generated',
      model: outcome.model,
    });

    if (error) {
      // A near-duplicate for this verse is refused by the database, which is
      // the guard working rather than a fault.
      results.rejected++;
      console.log(`  not stored for ${verse.reference}: ${error.message.slice(0, 120)}`);
    } else {
      results.written++;
      console.log(`  wrote one for ${verse.reference}`);
    }
  }

  await new Promise((r) => setTimeout(r, DELAY_MS));
}

console.log(
  `\nDone. ${results.written} written, ${results.rejected} rejected by the rules, `
  + `${results.failed} failed, ${results.rateLimited ? 'stopped on a rate limit' : 'no rate limiting'}.`,
);
if (!dryRun && results.written) {
  console.log('They are waiting for review at /admin/reminders.');
}
