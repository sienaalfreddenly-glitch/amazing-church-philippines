import { getSessionAndProfile } from '@/lib/supabase-server';
import { fetchDailyVerse } from '@/lib/bible';

export default async function DailyVerse() {
  const { user } = await getSessionAndProfile();
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD UTC
  const seed = user ? `${user.id}:${today}` : `guest:${today}`;

  let verse;
  try { verse = await fetchDailyVerse(seed); } catch { verse = null; }
  if (!verse) return null;

  const prettyDate = new Date().toLocaleDateString(undefined, { weekday:'long', month:'long', day:'numeric' });

  return (
    <section className="relative overflow-hidden rounded-3xl px-6 sm:px-10 py-10 sm:py-12 text-center animate-fade-up shadow-soft"
      style={{
        background:
          'radial-gradient(circle at 20% 0%, rgba(255,255,255,0.6), transparent 55%),' +
          'linear-gradient(135deg, #7A1F2B 0%, #B15564 100%)',
        color: 'white',
      }}>
      <p className="text-[11px] uppercase tracking-[0.3em] font-semibold opacity-80">{prettyDate}</p>
      <blockquote className="font-display text-2xl sm:text-3xl leading-snug mt-4 max-w-3xl mx-auto">
        <span className="text-4xl leading-none align-top opacity-60">“</span>
        {verse.text}
        <span className="text-4xl leading-none align-top opacity-60">”</span>
      </blockquote>
      <p className="mt-4 text-sm tracking-wider uppercase font-semibold opacity-90 flex items-center justify-center gap-2 flex-wrap">
        <span>— {verse.reference}</span>
        {verse.translation && (
          <span className="inline-block rounded-full bg-white/20 px-2 py-0.5 text-[10px] tracking-widest">
            {verse.translation}
          </span>
        )}
      </p>
    </section>
  );
}
