import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { readVisitorId } from '@/lib/visitor';

const TZ = 'Asia/Manila';

/**
 * Daily Bible Verse.
 *
 * A passage rather than a lone verse. Verse divisions cut across sentences, so
 * a single verse often reads as a fragment. The draw still picks one verse; the
 * database expands it to the surrounding sentences before it is shown.
 *
 * Everyone gets their own draw, and there is no global verse of the day, so two
 * readers may hold the same verse today. Members draw from the whole imported
 * Bible; visitors only from verses tagged with the welcoming themes, because
 * somebody's first encounter with this church should not be a random passage
 * from Judges.
 *
 * Nothing is chosen here. The database claims the verse and returns the same
 * one on every refresh, so a reload cannot change what a reader sees.
 */
export default async function DailyVerse() {
  const { user } = await getSessionAndProfile();
  const supabase = createClient();

  // A visitor id is created by the route handler, not here: a server component
  // cannot set cookies. Until one exists this renders the invitation below.
  const visitorId = user ? null : readVisitorId();

  const { data, error } = user
    ? await supabase.rpc('my_daily_content')
    : visitorId
      ? await supabase.rpc('visitor_daily_content', { p_visitor: visitorId })
      : { data: null, error: null };

  const entry = Array.isArray(data) ? data[0] : data;

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

        <blockquote className={`mx-auto mt-7 max-w-3xl ${
          entry.verse_text.length > 300 ? 'text-left' : ''
        }`}>
          {/* A passage runs longer than a single verse, so the size steps down
              in stages rather than dropping off a cliff at one threshold. */}
          <p className={`font-display font-bold ${
            entry.verse_text.length > 520 ? 'text-base leading-relaxed sm:text-lg'
            : entry.verse_text.length > 300 ? 'text-lg leading-relaxed sm:text-xl'
            : entry.verse_text.length > 170 ? 'text-xl leading-snug sm:text-2xl'
            : 'text-[1.6rem] leading-[1.3] sm:text-4xl'
          }`}>
            &ldquo;{entry.verse_text}&rdquo;
          </p>
          <cite className="mt-6 block text-sm font-semibold not-italic tracking-[0.06em] text-gilt-light">
            {entry.verse_ref}
          </cite>
        </blockquote>
      </div>
    </section>
  );
}
