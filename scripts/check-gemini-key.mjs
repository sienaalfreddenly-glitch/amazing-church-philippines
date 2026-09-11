/**
 * Check whether the configured Gemini key works, without printing it.
 *
 *   node scripts/check-gemini-key.mjs
 *
 * Reads GEMINI_API_KEY from deploy/.env or .env.local. Reports the length and
 * the last four characters only, which is enough to confirm you pasted the
 * whole thing without exposing the key in a terminal others may see.
 */
import { readFileSync } from 'node:fs';

function loadEnv(path) {
  try {
    for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
      const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
    }
  } catch { /* file may not exist yet */ }
}

loadEnv('deploy/.env');
loadEnv('.env.local');

const key = process.env.GEMINI_API_KEY;
if (!key) {
  console.log('GEMINI_API_KEY is not set in deploy/.env or .env.local.');
  process.exit(1);
}

console.log(`Key found: ${key.length} characters, ending ...${key.slice(-4)}`);

// Three ways Google accepts a key, so a failure is conclusive rather than a
// guess about which one this key wants.
const attempts = [
  ['x-goog-api-key header', 'https://generativelanguage.googleapis.com/v1beta/models', { 'x-goog-api-key': key }],
  ['key query parameter', `https://generativelanguage.googleapis.com/v1beta/models?key=${key}`, {}],
  ['bearer token', 'https://generativelanguage.googleapis.com/v1beta/models', { Authorization: `Bearer ${key}` }],
];

for (const [label, url, headers] of attempts) {
  try {
    const res = await fetch(url, { headers });
    if (res.ok) {
      const data = await res.json();
      const names = (data.models || []).map((m) => m.name.replace('models/', ''));
      console.log(`\nWorks via ${label}.`);
      console.log(`${names.length} models available. Flash models present: ${names.filter((n) => n.includes('flash')).slice(0, 4).join(', ') || 'none'}`);
      process.exit(0);
    }
    const body = await res.json().catch(() => ({}));
    console.log(`  ${label}: HTTP ${res.status} ${body?.error?.status || ''}`);
  } catch (err) {
    console.log(`  ${label}: ${err.message}`);
  }
}

console.log('\nNone of the three worked. Most likely the key was copied incompletely.');
console.log('Use the copy icon beside the key in AI Studio rather than selecting the text.');
process.exit(1);
