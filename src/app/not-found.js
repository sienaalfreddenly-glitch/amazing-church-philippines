import Link from 'next/link';
import { IconArrow } from '@/components/Icons';

export const metadata = { title: 'Page not found' };

export default function NotFound() {
  return (
    <section className="mx-auto max-w-xl py-16 text-center sm:py-24">
      <p className="nums font-display text-7xl text-brand-200 sm:text-8xl">404</p>

      <h1 className="mt-4 text-3xl sm:text-4xl">We could not find that page</h1>

      <p className="mx-auto mt-4 max-w-prose text-ink/65">
        The link may be old, or the post may have been taken down. Everything else is still
        where you left it.
      </p>

      <div className="mt-9 flex flex-wrap items-center justify-center gap-x-4 gap-y-3">
        <Link href="/" className="btn-primary group">
          <span>Back to home</span>
          <IconArrow size={16} className="transition-transform duration-200 group-hover:translate-x-1" />
        </Link>
        <Link href="/feed" className="btn-outline">Go to the feed</Link>
        <Link href="/events" className="btn-quiet">See upcoming events</Link>
      </div>
    </section>
  );
}
