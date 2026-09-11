import './globals.css';
import { Fraunces, Outfit } from 'next/font/google';
import Link from 'next/link';
import Navbar from '@/components/Navbar';
import { getSessionAndProfile } from '@/lib/supabase-server';

const sans = Outfit({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-sans',
  display: 'swap',
});

const display = Fraunces({
  subsets: ['latin'],
  weight: ['600', '700', '900'],
  variable: '--font-display',
  display: 'swap',
});

const SITE = 'Amazing Church Philippines';
const TAGLINE = 'Community, discussions, events and live worship.';

export const metadata = {
  metadataBase: new URL('https://amazing-church-philippines.vercel.app'),
  title: { default: SITE, template: `%s · ${SITE}` },
  description: TAGLINE,
  manifest: '/manifest.webmanifest',
  appleWebApp: { capable: true, title: 'Amazing Church', statusBarStyle: 'default' },
  openGraph: {
    type: 'website',
    siteName: SITE,
    title: SITE,
    description: TAGLINE,
    images: [{ url: '/logo.png', width: 1200, height: 630, alt: `${SITE} logo` }],
  },
  twitter: { card: 'summary_large_image', title: SITE, description: TAGLINE, images: ['/logo.png'] },
};

export const viewport = {
  themeColor: '#7A1F2B',
};

export default async function RootLayout({ children }) {
  const { profile } = await getSessionAndProfile();
  const year = new Date().getFullYear();

  return (
    <html lang="en" className={`${sans.variable} ${display.variable}`}>
      <body className="grain">
        <a href="#main" className="skip-link">Skip to content</a>

        <Navbar profile={profile} />

        <main id="main" className="mx-auto max-w-6xl px-4 pb-10 pt-8 animate-fade-up">
          {children}
        </main>

        <footer className="mt-20 border-t border-silver-light">
          <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-10 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="font-display text-lg text-brand">
                We win souls and make them disciples of Jesus
              </p>
              <p className="nums mt-2 text-sm text-ink/55">© {year} {SITE}</p>
            </div>
            <nav aria-label="Footer" className="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-ink/60">
              <Link href="/events" className="transition-colors hover:text-brand">Events</Link>
              <Link href="/live" className="transition-colors hover:text-brand">Live</Link>
              <Link href="/leaders" className="transition-colors hover:text-brand">Leaders</Link>
              <Link href="/privacy" className="transition-colors hover:text-brand">Privacy</Link>
              <Link href="/terms" className="transition-colors hover:text-brand">Terms</Link>
            </nav>
          </div>
        </footer>
      </body>
    </html>
  );
}
