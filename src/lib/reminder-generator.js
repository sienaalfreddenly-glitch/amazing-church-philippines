/**
 * Writing reminders with Gemini.
 *
 * Design decisions worth knowing:
 *
 * - Generation never happens while somebody is waiting. A background job tops
 *   up a buffer of approved reminders; the page only ever reads what already
 *   exists. If the model is slow, rate limited, or down, no reader notices.
 *
 * - Nothing generated is shown until a person approves it. This is commentary
 *   on Scripture published under the church's name.
 *
 * - Without GEMINI_API_KEY the module reports itself unavailable and the job
 *   exits quietly. The hand-written library keeps serving. Adding generation
 *   must never be able to break what already works.
 *
 * - The only thing sent to Google is a Bible verse and these instructions. No
 *   member data, no names, no posts. That matters because Google's free tier
 *   uses submitted content to improve their products.
 */

const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

// Flash is on the free tier and is more than capable of a short reflection.
const MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

/** Words that assume something about the reader's life. */
const ROLE_WORDS = /\b(parent|parents|mother|father|mum|dad|student|students|employee|employees|husband|wife|spouse|teenager|your kids|your children|your job|your boss|your marriage|your career)\b/i;

/** Phrases that promise an outcome nobody can promise. */
const OVERPROMISE = /\b(will heal you|will fix|guarantees?|everything will be (fine|okay|alright)|God will give you|all your problems)\b/i;

export function isGenerationAvailable() {
  return Boolean(process.env.GEMINI_API_KEY);
}

function buildPrompt(reference, verseText) {
  return `You are writing a short daily encouragement for a church website, to sit directly beneath this verse.

Verse: ${reference}
Text: ${verseText}

Write one reflection on this verse.

Rules, all of which matter:
- Speak to what the verse actually says. Do not write something generic that would fit any passage.
- Plain, everyday English. No church jargon, no words a newcomer would not know.
- Warm and honest. Never preachy, never cheerful about things that are hard.
- Address the reader as "you", but assume nothing about their life. They may or may not have children, a job, a partner, or good health. Do not guess.
- Do not promise that problems will be solved or that circumstances will change.
- No em dashes. No emoji. No hashtags. No headings. No quotation marks around the whole thing.
- Correct grammar and punctuation. Start with a capital letter and end with a full stop.
- As long as the thought needs and no longer. Two to five sentences is usually right.

Reply with the reflection only. No preamble, no title, no explanation.`;
}

/**
 * Every rule the text must satisfy, checked before it is stored.
 *
 * The database enforces most of these too. Checking here means a bad candidate
 * is discarded and retried rather than raising a constraint violation, and the
 * reason is legible in the job log.
 */
export function validateCandidate(text) {
  const problems = [];
  const clean = String(text ?? '').trim();

  if (!clean) problems.push('empty');
  if (!/^[A-Z]/.test(clean)) problems.push('does not start with a capital');
  if (!/[.!?]$/.test(clean)) problems.push('does not end with a full stop');
  if (/ {2,}/.test(clean)) problems.push('double spaces');
  if (/[.!?] +[a-z]/.test(clean)) problems.push('lowercase word after a sentence break');
  if (/[—–]/.test(clean)) problems.push('em dash');
  if (/[^\x00-\x7F‘’“”]/.test(clean)) problems.push('emoji or non-standard character');
  if (/#/.test(clean)) problems.push('hashtag');
  if (ROLE_WORDS.test(clean)) problems.push('assumes something about the reader');
  if (OVERPROMISE.test(clean)) problems.push('promises an outcome');
  // A model asked for prose sometimes returns a heading or a bulleted list.
  if (/^[-*#>]/m.test(clean)) problems.push('contains markdown formatting');

  return { ok: problems.length === 0, problems, text: clean };
}

/**
 * Ask Gemini for one reflection on one verse.
 *
 * Returns { ok, text } or { ok: false, reason }. Never throws: a background job
 * that dies on the first rate limit is worse than one that reports and moves on.
 */
export async function generateReminder({ reference, verseText, signal }) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) return { ok: false, reason: 'no GEMINI_API_KEY configured' };

  let res;
  try {
    res = await fetch(`${ENDPOINT}/${MODEL}:generateContent?key=${key}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal,
      body: JSON.stringify({
        contents: [{ parts: [{ text: buildPrompt(reference, verseText) }] }],
        generationConfig: {
          temperature: 1.0,   // Variety matters more than precision here.
          maxOutputTokens: 400,
        },
        // The verse itself can be violent or distressing, and a safety filter
        // tuned for chat will refuse to discuss it. These are set to block only
        // the clearly harmful, so Scripture is not treated as unsafe content.
        safetySettings: [
          'HARM_CATEGORY_HARASSMENT',
          'HARM_CATEGORY_HATE_SPEECH',
          'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'HARM_CATEGORY_DANGEROUS_CONTENT',
        ].map((category) => ({ category, threshold: 'BLOCK_ONLY_HIGH' })),
      }),
    });
  } catch (err) {
    return { ok: false, reason: `network: ${err.message}` };
  }

  if (res.status === 429) return { ok: false, reason: 'rate limited', retryable: true };
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    return { ok: false, reason: `HTTP ${res.status}: ${body.slice(0, 200)}` };
  }

  let data;
  try {
    data = await res.json();
  } catch {
    return { ok: false, reason: 'response was not JSON' };
  }

  const candidate = data?.candidates?.[0];
  if (!candidate) return { ok: false, reason: 'no candidate returned' };
  if (candidate.finishReason && candidate.finishReason !== 'STOP') {
    return { ok: false, reason: `finished as ${candidate.finishReason}` };
  }

  const raw = (candidate.content?.parts || []).map((p) => p.text || '').join(' ');
  const checked = validateCandidate(raw);
  if (!checked.ok) return { ok: false, reason: checked.problems.join(', ') };

  return { ok: true, text: checked.text, model: MODEL };
}
