import './globals.css';
import Navbar from '@/components/Navbar';
import { getSessionAndProfile } from '@/lib/supabase-server';

export const metadata = {
  title: 'Amazing Church Philippines',
  description: 'Community, discussions, events and live worship — Amazing Church Philippines',
  manifest: '/manifest.webmanifest',
  themeColor: '#7A1F2B',
  appleWebApp: { capable: true, title: 'Amazing Church', statusBarStyle: 'default' },
};

export default async function RootLayout({ children }) {
  const { profile } = await getSessionAndProfile();
  return (
    <html lang="en">
      <body>
        <Navbar profile={profile} />
        <main className="max-w-6xl mx-auto px-4 py-8 animate-fade-up">{children}</main>
        <footer className="border-t border-silver-light mt-16 py-8 text-center text-sm text-ink/60">
          <div className="max-w-6xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
            <p>© {new Date().getFullYear()} Amazing Church Philippines</p>
            <p className="text-brand font-semibold tracking-wide">We Win Souls and Make Them Disciples of Jesus</p>
          </div>
        </footer>
      </body>
    </html>
  );
}
