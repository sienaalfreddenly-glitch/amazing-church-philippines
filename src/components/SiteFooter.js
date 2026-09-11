import Link from 'next/link';
import Reveal from '@/components/Reveal';

/**
 * The final scene.
 *
 * Deliberately not a four-column link farm. It opens with one oversized line of
 * type carrying the church's own words, sets an arch silhouette behind it to
 * close the loop with the hero, and keeps the links to three honest groups.
 * Every link animates its own gilt underline on hover and focus, so keyboard
 * users see the same feedback as mouse users.
 */

const VISIT = [
  { href: '/events', label: 'Events' },
  { href: '/live', label: 'Live' },
  { href: '/news', label: 'News' },
];

const COMMUNITY = [
  { href: '/feed', label: 'Feed' },
  { href: '/discussions', label: 'Discussions' },
  { href: '/leaders', label: 'Leaders' },
];

const LEGAL = [
  { href: '/privacy', label: 'Privacy' },
  { href: '/terms', label: 'Terms' },
];

function LinkColumn({ heading, links, delay }) {
  return (
    <Reveal delay={delay} as="div">
      <h3 className="footer-heading">{heading}</h3>
      <ul className="footer-list">
        {links.map((l) => (
          <li key={l.href}>
            <Link href={l.href} className="footer-link">
              <span>{l.label}</span>
            </Link>
          </li>
        ))}
      </ul>
    </Reveal>
  );
}

export default function SiteFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="site-footer">
      {/* Arch silhouette: the same shape the hero flew through, now closing. */}
      <div aria-hidden="true" className="footer-arch" />

      <div className="footer-inner">
        <Reveal>
          <p className="footer-eyebrow gilt-text">Amazing Church Philippines</p>
          <p className="footer-statement">
            We win souls and make them disciples of Jesus
          </p>
        </Reveal>

        <div className="footer-columns">
          <LinkColumn heading="Visit" links={VISIT} delay={80} />
          <LinkColumn heading="Community" links={COMMUNITY} delay={160} />

          <Reveal delay={240} as="div">
            <h3 className="footer-heading">Find us</h3>
            <ul className="footer-list">
              <li>
                {/* REPLACE ME: the real Facebook page is wired through env. */}
                <a
                  href={process.env.NEXT_PUBLIC_FACEBOOK_PAGE_URL || 'https://www.facebook.com/amazingchurchphilippines'}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="footer-link"
                >
                  <span>Facebook</span>
                </a>
              </li>
              <li>
                <Link href="/signup" className="footer-link">
                  <span>Join the community</span>
                </Link>
              </li>
            </ul>
          </Reveal>
        </div>

        <Reveal delay={320} as="div" className="footer-baseline">
          <p className="nums">© {year} Amazing Church Philippines</p>
          <nav aria-label="Legal" className="footer-legal">
            {LEGAL.map((l) => (
              <Link key={l.href} href={l.href} className="footer-link">
                <span>{l.label}</span>
              </Link>
            ))}
          </nav>
        </Reveal>
      </div>
    </footer>
  );
}
