import Link from 'next/link';
import Image from 'next/image';
import FacebookEmbed from '@/components/FacebookEmbed';
import DailyVerse from '@/components/DailyVerse';
import HeroParallax from '@/components/HeroParallax';
import HeroSlideshow from '@/components/HeroSlideshow';
import Reveal from '@/components/Reveal';
import Spotlight from '@/components/Spotlight';
import Tilt3D from '@/components/Tilt3D';
import { IconChat, IconCamera, IconCalendar, IconUsers, IconMapPin, IconInbox, IconArrow } from '@/components/Icons';
import { createClient } from '@/lib/supabase-server';
import { eventDate, eventDateParts } from '@/lib/format';

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

  return (
    <div className="space-y-20 sm:space-y-28">
      {/* Hero — arched crown, the one church cue the whole page is built around */}
      <HeroParallax>
        <section
          className="relative isolate overflow-hidden rounded-[28px] px-6 py-20 text-center shadow-deep
                     sm:rounded-t-[140px] sm:rounded-b-[32px] sm:px-10 sm:pb-28 sm:pt-28
                     lg:rounded-t-[220px] lg:pt-32"
          style={{
            // Layered off-centre washes stand in when no hero slides are set,
            // so the section never renders as flat empty space.
            backgroundColor: '#FFFFFF',
            backgroundImage:
              'radial-gradient(760px 460px at 78% -12%, rgba(122,31,43,0.13), transparent 64%),' +
              'radial-gradient(620px 420px at 8% 106%, rgba(177,85,100,0.10), transparent 62%)',
          }}
        >
          <HeroSlideshow />

          {/* Soft centre scrim: holds headline contrast over whichever slide is
              showing, while the photograph still reads at the edges. */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-0"
            style={{
              background:
                'radial-gradient(62% 58% at 50% 52%, rgba(251,250,247,0.88) 0%, rgba(251,250,247,0.55) 55%, rgba(251,250,247,0) 100%)',
            }}
          />

          {/* Gilt inner rule tracing the arch, like leading in a window. */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-3 rounded-[22px] border border-gilt/25
                       sm:inset-5 sm:rounded-t-[124px] sm:rounded-b-[24px] lg:rounded-t-[200px]"
          />

          <div className="relative z-raised flex flex-col items-center">
            <Tilt3D max={10} scale={1.03} className="inline-block">
              <Image
                src="/logo.png"
                alt="Amazing Church Philippines"
                width={720}
                height={288}
                priority
                className="h-auto w-full max-w-[480px] animate-floaty"
                style={{ filter: 'drop-shadow(0 10px 26px rgba(38,9,13,0.4))' }}
              />
            </Tilt3D>

            <div className="mt-8 flex items-center gap-4">
              <span aria-hidden="true" className="h-px w-10 bg-gradient-to-r from-transparent to-gilt sm:w-16" />
              <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.38em]">Welcome home</p>
              <span aria-hidden="true" className="h-px w-10 bg-gradient-to-l from-transparent to-gilt sm:w-16" />
            </div>

            <h1 className="mt-5 max-w-4xl font-black text-[2.4rem] leading-[0.98] tracking-[-0.03em] text-ink sm:text-5xl lg:text-7xl">
              A church you can belong to <span className="text-brand">before</span> you believe
            </h1>

            <p className="mt-6 max-w-prose text-base leading-relaxed text-ink/70 sm:text-lg">
              Join the discussions, share what God is doing in your life, and stay close to every
              service, event, and livestream.
            </p>

            <div className="mt-10 flex flex-wrap items-center justify-center gap-x-4 gap-y-3">
              <Link href="/signup" className="btn-primary group px-6 py-3 text-base">
                <span>Join the community</span>
                <IconArrow size={17} className="transition-transform duration-200 group-hover:translate-x-1" />
              </Link>
              <Link href="/live" className="btn-outline px-5 py-3 text-base">Watch live</Link>
              <Link href="/events" className="btn-quiet">See what is on</Link>
            </div>
          </div>
        </section>
      </HeroParallax>

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
          <h2 className="text-2xl sm:text-3xl">From our Facebook page</h2>
          <p className="mt-1 text-sm text-ink/55">Livestreams and announcements, as they post.</p>
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
              <h2 className="text-2xl sm:text-3xl">Upcoming events</h2>
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
                  <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.26em]">Community</p>
                  <h3 className="mt-2 text-2xl text-white">Share what God is doing</h3>
                  <p className="mt-2 max-w-prose text-sm text-white/70">
                    Post a testimony, start a discussion, or encourage another member with a reaction or a comment.
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
