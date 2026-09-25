'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

/**
 * Navigation for the admin section.
 *
 * Every admin page used to carry its own row of buttons, or a lone "back" link,
 * so there was no way to move between them without returning to the landing
 * page first. This is one bar, present everywhere, that always says where you
 * are.
 *
 * Moderators see only what they can act on. Showing an admin-only tab that
 * refuses them on arrival wastes their time and looks broken.
 */

const TABS = [
  { href: '/admin', label: 'Queue', exact: true, admin: false },
  { href: '/admin/users', label: 'Members', admin: true },
  { href: '/admin/ministries', label: 'Ministries', admin: true },
  { href: '/admin/events', label: 'Events', admin: true },
  { href: '/admin/news', label: 'News', admin: true },
  { href: '/admin/courses', label: 'Courses', admin: true },
  { href: '/admin/hero-slides', label: 'Hero slides', admin: true },
  // Site copy is super-admin only; the layout still lets any admin *see* the
  // tab, but the page itself refuses non-super. Hiding it entirely from an
  // admin who is one click from becoming super feels furtive; the page's
  // refusal message is honest about the reason.
  { href: '/admin/content', label: 'Site copy', admin: true },
  { href: '/admin/church',  label: 'Church account', admin: true },
];

export default function AdminNav({ isAdmin }) {
  const pathname = usePathname();
  const tabs = TABS.filter((t) => !t.admin || isAdmin);

  return (
    <nav aria-label="Admin sections" className="admin-nav">
      <ul className="admin-tabs">
        {tabs.map((t) => {
          const active = t.exact ? pathname === t.href : pathname.startsWith(t.href);
          return (
            <li key={t.href}>
              <Link
                href={t.href}
                aria-current={active ? 'page' : undefined}
                className={`admin-tab ${active ? 'admin-tab-active' : ''}`}
              >
                {t.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
