import Link from 'next/link';
import Image from 'next/image';
import FacebookEmbed from '@/components/FacebookEmbed';
import DailyVerse from '@/components/DailyVerse';
import HeroParallax from '@/components/HeroParallax';
import HeroSlideshow from '@/components/HeroSlideshow';
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
    <div className="space-y-16 sm:space-y-20">
      {/* Hero */}
      <HeroParallax>
        <section
          className="relative isolate overflow-hidden rounded-[28px] px-6 py-16 text-center shadow-soft sm:px-10 sm:py-24"
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

          <div className="relative z-raised flex flex-col items-center">
            <Tilt3D max={10} scale={1.03} className="inline-block">
              <Image
                src="/logo.png"
                alt="Amazing Church Philippines"
                width={720}
                height={288}
                priority
                className="h-auto w-full max-w-[520px] animate-floaty"
                style={{ filter: 'drop-shadow(0 6px 18px rgba(38,9,13,0.35))' }}
              />
            </Tilt3D>

            <p className="mt-7 text-[11px] font-semibold uppercase tracking-[0.34em] text-brand">
              Welcome home
            </p>

            <h1 className="mt-3 max-w-3xl text-4xl text-ink sm:text-6xl">
              A church you can belong to <span className="text-brand">before</span> you believe
            </h1>

            <p className="mt-5 max-w-prose text-base leading-relaxed text-ink/70 sm:text-lg">
              Join the discussions, share what God is doing in your life, and stay close to every
              service, event, and livestream.
            </p>

            <div className="mt-8 flex flex-wrap items-center justify-center gap-x-4 gap-y-3">
              <Link href="/signup" className="btn-primary group">
                <span>Join the community</span>
                <IconArrow size={16} className="transition-transform duration-200 group-hover:translate-x-1" />
              </Link>
              <Link href="/live" className="btn-outline">Watch live</Link>
              <Link href="/events" className="btn-quiet">See what is on</Link>
            </div>
          </div>
        </section>
      </HeroParallax>

      {/* Daily Verse */}
      <DailyVerse />

      {/* Bento tiles */}
      <section aria-labelledby="explore-heading">
        <h2 id="explore-heading" className="sr-only">Explore the community</h2>
        <div className="grid auto-rows-[minmax(128px,auto)] grid-cols-1 gap-4 sm:grid-cols-4">
          {TILES.map((t, i) => (
            <Tilt3D key={t.title} fill max={t.feature ? 6 : 10} scale={1.02} className={t.span || ''}>
              <Link
                href={t.href}
                className={`card card-body group h-full animate-fade-up
                  ${t.feature ? 'sm:p-8' : ''}
                  ${t.wide ? 'sm:flex-row sm:items-center sm:gap-6' : ''}`}
                style={{ animationDelay: `${i * 70}ms` }}
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
                      ${t.feature ? 'text-2xl sm:text-3xl' : 'text-lg'}
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
            </Tilt3D>
          ))}
        </div>
      </section>

      {/* Facebook + events */}
      <section className="grid gap-10 md:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
        <div>
          <h2 className="text-2xl">From our Facebook page</h2>
          <p className="mt-1 text-sm text-ink/55">Livestreams and announcements, as they post.</p>
          <div className="mt-4">
            <Tilt3D max={4} scale={1.01}>
              <FacebookEmbed tabs="timeline" height={720} />
            </Tilt3D>
          </div>
        </div>

        <div className="space-y-8">
          <div>
            <div className="flex items-baseline justify-between gap-4">
              <h2 className="text-2xl">Upcoming events</h2>
              <Link href="/events" className="text-sm font-medium text-brand underline-offset-4 hover:underline">
                All events
              </Link>
            </div>

            <div className="mt-4 space-y-3">
              {events?.length ? (
                events.map((e, i) => {
                  const { day, month } = eventDateParts(e.starts_at);
                  return (
                    <Tilt3D key={e.id} max={6} scale={1.02}>
                      <div className="card flex animate-fade-up gap-4" style={{ animationDelay: `${i * 70}ms` }}>
                        {/* Compact date block gives every row the same left rail. */}
                        <div className="nums flex w-12 shrink-0 flex-col items-center justify-center rounded-xl bg-brand-50 py-2 text-brand">
                          <span className="text-xl font-semibold leading-none">{day}</span>
                          <span className="mt-0.5 text-[10px] font-semibold uppercase tracking-wider">{month}</span>
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
                    </Tilt3D>
                  );
                })
              ) : (
                <div className="card card-static py-10 text-center text-ink/60">
                  <div className="inline-block animate-floaty text-brand"><IconInbox size={40} /></div>
                  <p className="mt-3 font-medium text-ink/75">Nothing on the calendar yet</p>
                  <p className="mx-auto mt-1 max-w-xs text-sm">
                    Sunday service still runs every week. Watch it on the livestream page.
                  </p>
                  <Link href="/live" className="btn-outline mt-5">Watch live</Link>
                </div>
              )}
            </div>
          </div>

          <Tilt3D max={5} scale={1.02}>
            <div className="card card-body bg-brand-50/70">
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-brand">Community</p>
              <h3 className="mt-2 text-xl">Share what God is doing</h3>
              <p className="mt-2 max-w-prose text-sm text-ink/65">
                Post a testimony, start a discussion, or encourage another member with a reaction or a comment.
              </p>
              <div className="card-foot flex flex-wrap items-center gap-x-4 gap-y-3">
                <Link href="/feed" className="btn-primary">Go to feed</Link>
                <Link href="/discussions" className="btn-quiet">Browse discussions</Link>
              </div>
            </div>
          </Tilt3D>
        </div>
      </section>
    </div>
  );
}
