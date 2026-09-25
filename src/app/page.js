import Link from 'next/link';
import CinematicHero from '@/components/CinematicHero';
import FacebookEmbed from '@/components/FacebookEmbed';
import DailyVerse from '@/components/DailyVerse';
import Reveal from '@/components/Reveal';
import Spotlight from '@/components/Spotlight';
import Tilt3D from '@/components/Tilt3D';
import { IconChat, IconCamera, IconCalendar, IconUsers, IconMapPin, IconInbox, IconArrow } from '@/components/Icons';
import { createClient } from '@/lib/supabase-server';
import { eventDate, eventDateParts } from '@/lib/format';
import { getContent } from '@/lib/content';

// Re-render at least every minute so the Daily Verse rolls over promptly
// after midnight Asia/Manila (GMT+8).
export const revalidate = 60;

// Asymmetric bento: Discussions anchors the grid at 2x2, the rest fill in
// around it. Deliberately not four equal columns.
const TILES = [
  {
    Icon: IconChat,
    title: 'Discussions',
    text: 'Ask the questions you have been carrying. Answer someone else’s.',
    href: '/discussions',
    span: 'sm:col-span-2 sm:row-span-2',
    feature: true,
  },
  { Icon: IconCamera,   title: 'Feed',    text: 'Testimonies and moments from the week.', href: '/feed' },
  { Icon: IconCalendar, title: 'Events',  text: 'Services, outreach, and gatherings.',    href: '/events' },
  // Spans the remaining two columns so the second row closes flush rather
  // than leaving a hole at the end of the grid.
  {
    Icon: IconUsers,
    title: 'Leaders',
    text: 'The people shepherding each ministry.',
    href: '/leaders',
    span: 'sm:col-span-2',
    wide: true,
  },
];

export default async function Home() {
  const supabase = createClient();
  const { data: events } = await supabase
    .from('events').select('*').gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true }).limit(3);

  const [
    fbHeading, fbSubtitle, eventsHeading,
    communityEyebrow, communityHeading, communityBody,
  ] = await Promise.all([
    getContent('home.facebook.heading'),
    getContent('home.facebook.subtitle'),
    getContent('home.events.heading'),
    getContent('home.community.eyebrow'),
    getContent('home.community.heading'),
    getContent('home.community.body'),
  ]);

  return (
    <div className="space-y-20 sm:space-y-28">
      {/* Act one: the camera travels through the arch. */}
      <CinematicHero />

      {/* Daily Verse */}
      <Reveal>
        <DailyVerse />
      </Reveal>

      {/* Bento tiles */}
      <section aria-labelledby="explore-heading">
        <h2 id="explore-heading" className="sr-only">Explore the community</h2>

        <div className="grid auto-rows-[minmax(128px,auto)] grid-cols-1 gap-4 sm:grid-cols-4">
          {TILES.map((t, i) => (
            <Reveal key={t.title} delay={i * 90} className={`${t.span || ''} h-full`}>
              <Tilt3D fill max={t.feature ? 6 : 10} scale={1.02}>
                <Spotlight className="h-full rounded-2xl">
                  <Link
                    href={t.href}
                    className={`card card-body group h-full
                      ${t.feature ? 'sm:p-8' : ''}
                      ${t.wide ? 'sm:flex-row sm:items-center sm:gap-6' : ''}`}
                  >
                    <div
                      className="shrink-0 text-brand transition-transform duration-300 group-hover:-translate-y-1 group-hover:scale-110"
                      style={{ transform: 'translateZ(30px)' }}
                    >
                      <t.Icon size={t.feature ? 44 : 30} />
                    </div>

                    <div className={t.wide ? 'sm:min-w-0' : 'contents'}>
                      <h3
                        className={`mt-4 transition-colors group-hover:text-brand
                          ${t.feature ? 'text-2xl sm:text-4xl' : 'text-lg'}
                          ${t.wide ? 'sm:mt-0' : ''}`}
                        style={{ transform: 'translateZ(15px)' }}
                      >
                        {t.title}
                      </h3>

                      <p
                        className={`mt-1.5 text-ink/60 ${t.feature ? 'max-w-prose text-base' : 'text-sm'}`}
                        style={{ transform: 'translateZ(8px)' }}
                      >
                        {t.text}
                      </p>
                    </div>

                    {t.feature && (
                      <span className="card-foot inline-flex items-center gap-1.5 text-sm font-semibold text-brand">
                        Open discussions
                        <IconArrow size={15} className="transition-transform duration-200 group-hover:translate-x-1" />
                      </span>
                    )}
                  </Link>
                </Spotlight>
              </Tilt3D>
            </Reveal>
          ))}
        </div>
      </section>

      {/* Facebook + events */}
      <section className="grid gap-12 md:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
        <Reveal>
          <h2 className="text-2xl sm:text-3xl">{fbHeading}</h2>
          <p className="mt-1 text-sm text-ink/55">{fbSubtitle}</p>
          <hr className="gilt-rule mt-5" />
          <div className="mt-6">
            <Tilt3D max={4} scale={1.01}>
              <FacebookEmbed tabs="timeline" height={720} />
            </Tilt3D>
          </div>
        </Reveal>

        <div className="space-y-10">
          <Reveal delay={120}>
            <div className="flex items-baseline justify-between gap-4">
              <h2 className="text-2xl sm:text-3xl">{eventsHeading}</h2>
              <Link href="/events" className="text-sm font-medium text-brand underline-offset-4 hover:underline">
                All events
              </Link>
            </div>
            <hr className="gilt-rule mt-5" />

            <div className="mt-6 space-y-3">
              {events?.length ? (
                events.map((e, i) => {
                  const { day, month } = eventDateParts(e.starts_at);
                  return (
                    <Reveal key={e.id} delay={i * 90}>
                      <Tilt3D max={6} scale={1.02}>
                        <Spotlight className="rounded-2xl">
                          <div className="card flex gap-4">
                            {/* Compact date block gives every row the same left rail. */}
                            <div className="nums flex w-14 shrink-0 flex-col items-center justify-center rounded-xl bg-brand py-2.5 text-white shadow-gilt">
                              <span className="text-xl font-semibold leading-none">{day}</span>
                              <span className="mt-1 text-[10px] font-semibold uppercase tracking-wider text-gilt-light">
                                {month}
                              </span>
                            </div>
                            <div className="min-w-0">
                              <h3 className="text-lg">{e.title}</h3>
                              <p className="nums mt-0.5 text-xs font-medium text-ink/55">{eventDate(e.starts_at)}</p>
                              {e.location && (
                                <p className="mt-1.5 inline-flex items-center gap-1 text-sm text-ink/60">
                                  <IconMapPin size={14} /> {e.location}
                                </p>
                              )}
                            </div>
                          </div>
                        </Spotlight>
                      </Tilt3D>
                    </Reveal>
                  );
                })
              ) : (
                <div className="card card-static py-12 text-center text-ink/60">
                  <div className="inline-block animate-floaty text-brand"><IconInbox size={40} /></div>
                  <p className="mt-4 font-medium text-ink/75">Nothing on the calendar yet</p>
                  <p className="mx-auto mt-1 max-w-xs text-sm">
                    Sunday service still runs every week. Watch it on the livestream page.
                  </p>
                  <Link href="/live" className="btn-outline mt-6">Watch live</Link>
                </div>
              )}
            </div>
          </Reveal>

          <Reveal delay={200}>
            <Tilt3D max={5} scale={1.02}>
              <Spotlight className="rounded-2xl">
                {/* Deep brand panel — the one weighted surface on a light page,
                    matched to the verse band so it reads as a set, not an accident. */}
                <div
                  className="card card-body overflow-hidden text-white shadow-deep"
                  style={{
                    backgroundColor: '#661923',
                    backgroundImage:
                      'radial-gradient(420px 260px at 12% 4%, rgba(177,85,100,0.75), transparent 66%),' +
                      'radial-gradient(360px 280px at 94% 98%, rgba(38,9,13,0.7), transparent 62%)',
                  }}
                >
                  <p className="gilt-text-bright text-[11px] font-semibold uppercase tracking-[0.26em]">{communityEyebrow}</p>
                  <h3 className="mt-2 text-2xl text-white">{communityHeading}</h3>
                  <p className="mt-2 max-w-prose text-sm text-white/70 whitespace-pre-line">
                    {communityBody}
                  </p>
                  <div className="card-foot flex flex-wrap items-center gap-x-4 gap-y-3">
                    <Link href="/feed" className="btn-outline border-gilt/40 bg-white/10 text-white hover:bg-white/20">
                      Go to feed
                    </Link>
                    <Link href="/discussions" className="btn-quiet text-white/80 decoration-gilt hover:text-white">
                      Browse discussions
                    </Link>
                  </div>
                </div>
              </Spotlight>
            </Tilt3D>
          </Reveal>
        </div>
      </section>
    </div>
  );
}
