import Link from 'next/link';
import Image from 'next/image';
import FacebookEmbed from '@/components/FacebookEmbed';
import DailyVerse from '@/components/DailyVerse';
import HeroParallax from '@/components/HeroParallax';
import HeroSlideshow from '@/components/HeroSlideshow';
import Tilt3D from '@/components/Tilt3D';
import { IconChat, IconCamera, IconCalendar, IconUsers, IconMapPin, IconInbox, IconArrow } from '@/components/Icons';
import { createClient } from '@/lib/supabase-server';

// Re-render at least every minute so the Daily Verse rolls over promptly
// after midnight Asia/Manila (GMT+8).
export const revalidate = 60;

export default async function Home() {
  const supabase = createClient();
  const { data: events } = await supabase
    .from('events').select('*').gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true }).limit(3);

  return (
    <div className="space-y-14">
      {/* Hero */}
      <HeroParallax>
        <section className="relative text-center px-6 sm:px-10 py-16 sm:py-20 animate-fade-up bg-brand-flow overflow-hidden"
          style={{
            backgroundImage:
              'linear-gradient(135deg, #FFFFFF 0%, #FBFAF7 60%, rgba(122,31,43,0.05) 100%)',
          }}>
          <HeroSlideshow />
          <div className="relative z-10 flex flex-col items-center">
            <Tilt3D max={10} scale={1.03} className="inline-block">
              <Image src="/logo.png" alt="Amazing Church Philippines"
                width={720} height={288} priority
                className="w-full max-w-[560px] h-auto animate-floaty"
                style={{ filter: 'drop-shadow(0 4px 14px rgba(0,0,0,0.35))' }} />
            </Tilt3D>
            <span className="mt-6 inline-block rounded-full bg-white/85 backdrop-blur px-4 py-1.5 text-xs font-semibold tracking-[0.3em] uppercase text-brand shadow-soft border border-brand/10">
              Welcome Home
            </span>
            <h1 className="font-display text-3xl sm:text-5xl mt-4 leading-tight text-ink"
              style={{ textShadow: '0 2px 12px rgba(255,255,255,0.9), 0 1px 2px rgba(255,255,255,0.7)' }}>
              Amazing Church <span className="text-brand">Philippines</span>
            </h1>
            <p className="mt-4 text-ink max-w-2xl text-base sm:text-lg"
              style={{ textShadow: '0 1px 6px rgba(255,255,255,0.85)' }}>
              A gathering place for our community — join discussions, share what God is doing in your life,
              and stay connected to every service, event, and livestream.
            </p>
            <div className="mt-7 flex justify-center gap-3 flex-wrap">
              <Link href="/signup" className="btn-primary group">
                <span>Join the community</span>
                <IconArrow size={16} className="transition-transform group-hover:translate-x-1" />
              </Link>
              <Link href="/live" className="btn-outline">Watch live</Link>
            </div>
          </div>
        </section>
      </HeroParallax>

      {/* Daily Verse */}
      <DailyVerse />

      {/* Feature strip */}
      <section className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { Icon: IconChat,     title: 'Discussions', text: 'Ask, share, and grow together.', href: '/discussions' },
          { Icon: IconCamera,   title: 'Feed',        text: 'Testimonies and moments.',      href: '/feed' },
          { Icon: IconCalendar, title: 'Events',      text: 'What’s happening next.',        href: '/events' },
          { Icon: IconUsers,    title: 'Leaders',     text: 'Meet our shepherds.',           href: '/leaders' },
        ].map((f, i) => (
          <Tilt3D key={f.title} max={10} scale={1.03}>
            <Link href={f.href}
              className="card block group animate-fade-up"
              style={{ animationDelay: `${i * 60}ms` }}>
              <div className="text-brand transition-transform group-hover:scale-110 group-hover:-translate-y-1"
                style={{ transform: 'translateZ(30px)' }}>
                <f.Icon size={32} />
              </div>
              <h3 className="text-lg mt-3 group-hover:text-brand transition-colors"
                style={{ transform: 'translateZ(15px)' }}>{f.title}</h3>
              <p className="text-sm text-ink/60"
                style={{ transform: 'translateZ(8px)' }}>{f.text}</p>
            </Link>
          </Tilt3D>
        ))}
      </section>

      {/* FB + events */}
      <section className="grid md:grid-cols-2 gap-8">
        <div>
          <h2 className="text-2xl mb-3 flex items-center gap-2">
            <span>From our Facebook page</span>
            <span className="badge bg-brand-50 text-brand">Live-ready</span>
          </h2>
          <Tilt3D max={4} scale={1.01}>
            <FacebookEmbed tabs="timeline" height={720} />
          </Tilt3D>
        </div>

        <div className="space-y-6">
          <div>
            <h2 className="text-2xl mb-3">Upcoming events</h2>
            <div className="space-y-3">
              {events?.length ? events.map((e, i) => (
                <Tilt3D key={e.id} max={6} scale={1.02}>
                  <div className="card animate-fade-up" style={{ animationDelay: `${i * 60}ms` }}>
                    <p className="text-xs text-brand uppercase tracking-wider font-semibold">
                      {new Date(e.starts_at).toLocaleString()}
                    </p>
                    <h3 className="text-lg mt-1">{e.title}</h3>
                    {e.location && (
                      <p className="text-sm text-ink/60 mt-1 inline-flex items-center gap-1">
                        <IconMapPin size={14} /> {e.location}
                      </p>
                    )}
                  </div>
                </Tilt3D>
              )) : (
                <div className="card text-center text-ink/60 py-8">
                  <div className="text-brand animate-floaty inline-block"><IconInbox size={40} /></div>
                  <p className="mt-2">No upcoming events yet — check back soon.</p>
                </div>
              )}
            </div>
          </div>

          <Tilt3D max={5} scale={1.02}>
            <div className="card"
              style={{ background: 'linear-gradient(135deg, rgba(122,31,43,0.05), rgba(177,85,100,0.03))' }}>
              <p className="text-brand font-semibold uppercase text-xs tracking-widest">Community</p>
              <h3 className="text-xl mt-1">Share what God is doing.</h3>
              <p className="text-sm text-ink/60 mt-2">
                Post a testimony, start a discussion, or send love to another member with a reaction or a comment.
              </p>
              <div className="mt-4 flex gap-2 flex-wrap">
                <Link href="/feed" className="btn-primary">Go to feed</Link>
                <Link href="/discussions" className="btn-outline">Discussions</Link>
              </div>
            </div>
          </Tilt3D>
        </div>
      </section>
    </div>
  );
}
