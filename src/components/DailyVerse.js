import { createClient, getSessionAndProfile } from '@/lib/supabase-server';

const TZ = 'Asia/Manila';

/**
 * Daily Bible Verse.
 *
 * Exactly two sections: the verse, and Today's Reminder. No lesson, no prayer.
 *
 * The content is claimed from the database by my_daily_content(), which assigns
 * the signed-in user a pair nobody else holds today and returns the same pair on
 * every refresh. Nothing is chosen here, so a reload cannot produce different
 * content and two readers cannot be handed the same verse.
 *
 * Signed-out visitors see nothing. An assignment belongs to a person, and there
 * is no such thing as an anonymous one.
 */
export default async function DailyVerse() {
  const { user } = await getSessionAndProfile();
  if (!user) return null;

  const supabase = createClient();
  const { data, error } = await supabase.rpc('my_daily_content');
  const entry = Array.isArray(data) ? data[0] : data;

  // Pool exhausted for today, or the call failed. Say so plainly rather than
  // showing somebody else's verse or an empty box.
  if (error || !entry) {
    return (
      <section
        aria-labelledby="daily-verse-heading"
        className="rounded-3xl px-6 py-10 text-center shadow-soft ring-1 ring-silver-light sm:px-12"
      >
        <h2 id="daily-verse-heading" className="text-2xl">Daily Bible Verse</h2>
        <p className="mx-auto mt-3 max-w-prose text-ink/60">
          Today&apos;s verse is not ready yet. Please check back shortly.
        </p>
      </section>
    );
  }

  const prettyDate = new Intl.DateTimeFormat('en-PH', {
    timeZone: TZ, weekday: 'long', month: 'long', day: 'numeric',
  }).format(new Date(`${entry.assigned_on}T00:00:00`));

  return (
    <section
      aria-labelledby="daily-verse-heading"
      className="relative overflow-hidden rounded-3xl px-6 py-14 text-center text-white shadow-deep sm:px-12 sm:py-16"
      style={{
        backgroundColor: '#661923',
        backgroundImage:
          'radial-gradient(680px 420px at 18% 6%, rgba(177,85,100,0.85), transparent 66%),' +
          'radial-gradient(520px 380px at 92% 96%, rgba(122,31,43,0.95), transparent 62%),' +
          'radial-gradient(900px 520px at 50% 120%, rgba(38,9,13,0.55), transparent 70%)',
      }}
    >
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 opacity-[0.07] mix-blend-overlay"
        style={{
          backgroundImage:
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='v'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='4'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23v)'/%3E%3C/svg%3E\")",
        }}
      />
      <div aria-hidden="true" className="pointer-events-none absolute inset-4 rounded-2xl border border-gilt/30 sm:inset-6" />

      <div className="relative">
        <h2 id="daily-verse-heading" className="gilt-text text-[11px] font-semibold uppercase tracking-[0.32em]">
          Daily Bible Verse
        </h2>
        <p className="nums mt-2 text-[11px] font-medium uppercase tracking-[0.2em] text-white/50">
          {prettyDate}
        </p>

        <blockquote className="mx-auto mt-7 max-w-3xl">
          <p className={`font-display font-bold leading-[1.3] ${
            entry.verse_text.length > 190 ? 'text-xl sm:text-2xl' : 'text-[1.6rem] sm:text-4xl'
          }`}>
            &ldquo;{entry.verse_text}&rdquo;
          </p>
          <cite className="mt-5 block text-sm font-semibold not-italic tracking-[0.06em] text-gilt-light">
            {entry.verse_ref}
          </cite>
        </blockquote>

        <hr className="gilt-rule mx-auto mt-9 w-24" />

        <div className="mx-auto mt-8 max-w-prose">
          <h3 className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gilt-light/80">
            Today&apos;s Reminder
          </h3>
          <p className="mt-4 text-left leading-relaxed text-white/85 sm:text-center">
            {entry.reminder}
          </p>
        </div>
      </div>
    </section>
  );
}
