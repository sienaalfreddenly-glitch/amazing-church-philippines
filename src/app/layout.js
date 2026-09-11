import './globals.css';
import './cinema.css';
import { Fraunces, Outfit } from 'next/font/google';
import Navbar from '@/components/Navbar';
import SiteFooter from '@/components/SiteFooter';
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

  return (
    <html lang="en" className={`${sans.variable} ${display.variable}`}>
      <body className="grain">
        <a href="#main" className="skip-link">Skip to content</a>

        <Navbar profile={profile} />

        <main id="main" className="mx-auto max-w-6xl px-4 pb-10 pt-8 animate-fade-up">
          {children}
        </main>

        <SiteFooter />
      </body>
    </html>
  );
}
