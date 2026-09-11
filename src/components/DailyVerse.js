import { getSessionAndProfile } from '@/lib/supabase-server';
import { fetchDailyVerse } from '@/lib/bible';

const TZ = 'Asia/Manila';

// YYYY-MM-DD in Manila (rolls over at 12 midnight PHT, GMT+8)
function manilaDateKey() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date());
}

export default async function DailyVerse() {
  const { user } = await getSessionAndProfile();
  const today = manilaDateKey();                                  // e.g. "2026-07-21"
  const seed = user ? `${user.id}:${today}` : `guest:${today}`;

  let verse;
  try { verse = await fetchDailyVerse(seed); } catch { verse = null; }
  if (!verse) return null;

  const prettyDate = new Intl.DateTimeFormat('en-US', {
    timeZone: TZ, weekday: 'long', month: 'long', day: 'numeric',
  }).format(new Date());

  return (
    <section
      aria-label="Verse of the day"
      className="relative overflow-hidden rounded-3xl px-6 py-14 text-center text-white shadow-deep sm:px-12 sm:py-20"
      style={{
        // Three off-centre radial stops instead of one even linear fade, so the
        // surface has a light source rather than a uniform ramp.
        backgroundColor: '#661923',
        backgroundImage:
          'radial-gradient(680px 420px at 18% 6%, rgba(177,85,100,0.85), transparent 66%),' +
          'radial-gradient(520px 380px at 92% 96%, rgba(122,31,43,0.95), transparent 62%),' +
          'radial-gradient(900px 520px at 50% 120%, rgba(38,9,13,0.55), transparent 70%)',
      }}
    >
      {/* Grain breaks the flatness of a large single-colour field. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 opacity-[0.07] mix-blend-overlay"
        style={{
          backgroundImage:
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='v'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='4'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23v)'/%3E%3C/svg%3E\")",
        }}
      />

      {/* Gilt inset rule — a frame around scripture, the way a plaque is set. */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-4 rounded-2xl border border-gilt/30 sm:inset-6" />

      <div className="relative">
        <p className="nums text-[11px] font-semibold uppercase tracking-[0.32em] text-gilt-light/80">{prettyDate}</p>

        {/* The quote mark is positioned out of the text flow — as an inline
            glyph it inflated the first line box and opened a gap under it. */}
        <div className="relative mx-auto mt-6 max-w-3xl">
          <span
            aria-hidden="true"
            className="pointer-events-none absolute -left-1 -top-7 select-none font-display text-6xl leading-none text-white/25 sm:-left-6 sm:-top-8 sm:text-7xl"
          >
            “
          </span>

          <blockquote
            className={`relative font-display leading-[1.3] ${
              // Long passages drop a step so a genealogy does not fill the
              // viewport at the same scale as a one-line psalm.
              verse.text.length > 190 ? 'text-xl sm:text-2xl' : 'text-[1.6rem] sm:text-4xl'
            }`}
          >
            {verse.text}
          </blockquote>
        </div>

        <hr className="gilt-rule mx-auto mt-8 w-24" />

        <p className="mt-5 flex flex-wrap items-center justify-center gap-2.5 text-sm font-semibold tracking-[0.06em] text-white/85">
          <span>{verse.reference}</span>
          {verse.translation && (
            <span className="badge bg-white/15 text-[10px] tracking-[0.14em] text-white/80">
              {verse.translation}
            </span>
          )}
        </p>
      </div>
    </section>
  );
}
