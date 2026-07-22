import Link from 'next/link';
import Image from 'next/image';
import { isStaff, isAdmin } from '@/lib/roles';
import LogoutButton from './LogoutButton';
import Avatar from './Avatar';
import NotificationBell from './NotificationBell';

export default function Navbar({ profile }) {
  const isMember = profile?.account_status === 'approved';
  const links = isMember ? [
    { href: '/', label: 'Home' },
    { href: '/news', label: 'News' },
    { href: '/feed', label: 'Feed' },
    { href: '/discussions', label: 'Discussions' },
    { href: '/leaders', label: 'Leaders' },
    { href: '/courses', label: 'Courses' },
    { href: '/events', label: 'Events' },
    { href: '/live', label: 'Live' },
  ] : [
    { href: '/', label: 'Home' },
    { href: '/news', label: 'News' },
    { href: '/events', label: 'Events' },
    { href: '/live', label: 'Live' },
  ];
  return (
    <header className="sticky top-0 z-40 nav-blur border-b border-silver-light">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between gap-4">
        <Link href="/" className="flex items-center gap-3 shrink-0">
          <Image src="/logo.png" alt="Amazing Church Philippines"
            width={200} height={60} priority
            className="h-10 w-auto" />
        </Link>
        <nav className="flex items-center gap-1 overflow-x-auto">
          {links.map(l => (
            <Link key={l.href} href={l.href}
              className="px-3 py-2 rounded text-sm hover:bg-silver-light text-ink/80 whitespace-nowrap">{l.label}</Link>
          ))}
          {profile && isStaff(profile.role) && (
            <Link href="/admin" className="px-3 py-2 rounded text-sm text-brand font-semibold hover:bg-brand-50 whitespace-nowrap">
              {isAdmin(profile.role) ? 'Admin' : 'Moderate'}
            </Link>
          )}
        </nav>
        <div className="flex items-center gap-2 shrink-0">
          {profile ? (
            <>
              <NotificationBell />
              <Link href="/account" className="flex items-center gap-2 hover:opacity-80">
                <Avatar url={profile.avatar_url} name={profile.full_name} size={32} />
                <span className="hidden md:inline text-sm text-ink/70">{profile.full_name.split(' ')[0]}</span>
              </Link>
              <LogoutButton />
            </>
          ) : (
            <>
              <Link href="/login" className="btn-outline">Log in</Link>
              <Link href="/signup" className="btn-primary">Sign up</Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
