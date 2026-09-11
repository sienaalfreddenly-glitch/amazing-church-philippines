import Link from 'next/link';
import Image from 'next/image';
import { isStaff, isAdmin } from '@/lib/roles';
import LogoutButton from './LogoutButton';
import Avatar from './Avatar';
import NavLinks from './NavLinks';
import NotificationBell from './NotificationBell';

export default function Navbar({ profile }) {
  const isMember = profile?.account_status === 'approved';

  const links = isMember
    ? [
        { href: '/', label: 'Home' },
        { href: '/news', label: 'News' },
        { href: '/feed', label: 'Feed' },
        { href: '/discussions', label: 'Discussions' },
        { href: '/leaders', label: 'Leaders' },
        { href: '/courses', label: 'Courses' },
        { href: '/events', label: 'Events' },
        { href: '/live', label: 'Live' },
      ]
    : [
        { href: '/', label: 'Home' },
        { href: '/news', label: 'News' },
        { href: '/events', label: 'Events' },
        { href: '/live', label: 'Live' },
      ];

  if (profile && isStaff(profile.role)) {
    links.push({
      href: '/admin',
      label: isAdmin(profile.role) ? 'Admin' : 'Moderate',
      accent: true,
    });
  }

  return (
    <header className="sticky top-0 z-sticky nav-blur">
      <div className="relative mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4">
        <Link href="/" className="shrink-0" aria-label="Amazing Church Philippines — home">
          <Image
            src="/logo.png"
            alt="Amazing Church Philippines"
            width={200}
            height={60}
            priority
            className="h-10 w-auto"
          />
        </Link>

        <NavLinks links={links} />

        <div className="flex shrink-0 items-center gap-2">
          {profile ? (
            <>
              <NotificationBell />
              <Link
                href="/account"
                className="flex items-center gap-2 rounded-lg p-1 transition-opacity hover:opacity-80"
              >
                <Avatar url={profile.avatar_url} name={profile.full_name} size={32} />
                <span className="hidden text-sm text-ink/70 md:inline">
                  {profile.full_name.split(' ')[0]}
                </span>
              </Link>
              <LogoutButton />
            </>
          ) : (
            <>
              <Link href="/login" className="btn-quiet">Log in</Link>
              <Link href="/signup" className="btn-primary">Sign up</Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
