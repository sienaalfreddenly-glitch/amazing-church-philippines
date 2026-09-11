'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

function isActive(pathname, href) {
  return href === '/' ? pathname === '/' : pathname.startsWith(href);
}

/**
 * Primary navigation. Inline on desktop, a disclosure panel on mobile —
 * replaces the horizontally scrolling link strip, which hid destinations
 * off the right edge with no affordance that they existed.
 */
export default function NavLinks({ links }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  // Any navigation closes the panel.
  useEffect(() => { setOpen(false); }, [pathname]);

  // Escape closes it too, for keyboard users.
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <>
      <nav aria-label="Primary" className="hidden items-center gap-0.5 lg:flex">
        {links.map((l) => {
          const active = isActive(pathname, l.href);
          return (
            <Link
              key={l.href}
              href={l.href}
              aria-current={active ? 'page' : undefined}
              className={`relative whitespace-nowrap rounded-lg px-3 py-2 text-sm transition-colors duration-200
                ${l.accent ? 'font-semibold text-brand hover:bg-brand-50' : ''}
                ${active && !l.accent ? 'font-semibold text-brand' : ''}
                ${!active && !l.accent ? 'text-ink/70 hover:bg-silver-light hover:text-ink' : ''}`}
            >
              {l.label}
              {active && (
                <span
                  aria-hidden="true"
                  className="absolute inset-x-3 -bottom-0.5 h-0.5 rounded-full bg-brand"
                />
              )}
            </Link>
          );
        })}
      </nav>

      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-controls="mobile-nav"
        aria-label={open ? 'Close menu' : 'Open menu'}
        className="rounded-lg p-2 text-ink/70 transition-colors hover:bg-silver-light hover:text-ink lg:hidden"
      >
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor"
          strokeWidth="1.75" strokeLinecap="round" aria-hidden="true">
          {open ? <path d="M6 6l12 12M18 6L6 18" /> : <path d="M4 7h16M4 12h16M4 17h16" />}
        </svg>
      </button>

      {open && (
        <nav
          id="mobile-nav"
          aria-label="Primary"
          className="absolute inset-x-0 top-16 z-overlay animate-fade-up border-b border-silver-light bg-paper
                     px-4 pb-4 pt-2 shadow-lift lg:hidden"
        >
          {links.map((l) => {
            const active = isActive(pathname, l.href);
            return (
              <Link
                key={l.href}
                href={l.href}
                aria-current={active ? 'page' : undefined}
                className={`block rounded-lg px-3 py-2.5 text-sm transition-colors
                  ${active ? 'bg-brand-50 font-semibold text-brand' : 'text-ink/75 hover:bg-silver-light'}
                  ${l.accent ? 'font-semibold text-brand' : ''}`}
              >
                {l.label}
              </Link>
            );
          })}
        </nav>
      )}
    </>
  );
}
