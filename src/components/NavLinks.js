'use client';
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

/**
 * Primary navigation.
 *
 * A signed-in member had eleven top-level links, which is not a menu so much as
 * a list. Only the handful of places people go every week sit in the bar now;
 * the rest live behind More. Admin stays out on its own because staff need to
 * reach it in a hurry and it is the one destination with consequences.
 *
 * Inline on desktop, a disclosure panel on mobile.
 */

function isActive(pathname, href) {
  return href === '/' ? pathname === '/' : pathname.startsWith(href);
}

export default function NavLinks({ primary, more, admin }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const moreRef = useRef(null);

  useEffect(() => { setOpen(false); setMoreOpen(false); }, [pathname]);

  useEffect(() => {
    if (!open && !moreOpen) return;
    const onKey = (e) => { if (e.key === 'Escape') { setOpen(false); setMoreOpen(false); } };
    // A click anywhere else closes the More menu, which is what people expect
    // of a dropdown and what keyboard Escape alone does not cover.
    const onDown = (e) => {
      if (moreRef.current && !moreRef.current.contains(e.target)) setMoreOpen(false);
    };
    window.addEventListener('keydown', onKey);
    window.addEventListener('pointerdown', onDown);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('pointerdown', onDown);
    };
  }, [open, moreOpen]);

  const linkClass = (l, active) =>
    `relative whitespace-nowrap rounded-lg px-3 py-2 text-sm transition-colors duration-200
     ${active ? 'font-semibold text-brand' : 'text-ink/70 hover:bg-silver-light hover:text-ink'}`;

  const moreHasActive = more.some((l) => isActive(pathname, l.href));

  return (
    <>
      <nav aria-label="Primary" className="hidden items-center gap-0.5 lg:flex">
        {primary.map((l) => {
          const active = isActive(pathname, l.href);
          return (
            <Link key={l.href} href={l.href} aria-current={active ? 'page' : undefined} className={linkClass(l, active)}>
              {l.label}
              {active && (
                <span aria-hidden="true" className="absolute inset-x-3 -bottom-0.5 h-0.5 rounded-full bg-brand" />
              )}
            </Link>
          );
        })}

        {more.length > 0 && (
          <div ref={moreRef} className="relative">
            <button
              type="button"
              onClick={() => setMoreOpen((v) => !v)}
              aria-expanded={moreOpen}
              aria-haspopup="true"
              className={`inline-flex items-center gap-1 rounded-lg px-3 py-2 text-sm transition-colors
                ${moreHasActive ? 'font-semibold text-brand' : 'text-ink/70 hover:bg-silver-light hover:text-ink'}`}
            >
              More
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                strokeWidth="2" strokeLinecap="round" aria-hidden="true"
                className={`transition-transform duration-200 ${moreOpen ? 'rotate-180' : ''}`}>
                <path d="M6 9l6 6 6-6" />
              </svg>
            </button>

            {moreOpen && (
              <div className="absolute right-0 top-full z-overlay mt-2 w-52 rounded-xl bg-white p-1.5 shadow-lift animate-fade-up">
                {more.map((l) => {
                  const active = isActive(pathname, l.href);
                  return (
                    <Link
                      key={l.href}
                      href={l.href}
                      aria-current={active ? 'page' : undefined}
                      className={`block rounded-lg px-3 py-2 text-sm transition-colors
                        ${active ? 'bg-brand-50 font-semibold text-brand' : 'text-ink/75 hover:bg-silver-light'}`}
                    >
                      {l.label}
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {admin && (
          <Link
            href={admin.href}
            className="ml-1 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-semibold text-brand transition-colors hover:bg-brand-50"
          >
            {admin.label}
          </Link>
        )}
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
          {[...primary, ...more, ...(admin ? [admin] : [])].map((l) => {
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
