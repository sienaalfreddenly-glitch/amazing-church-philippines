'use client';

import Link from 'next/link';

export default function Error({ error, reset }) {
  return (
    <section className="mx-auto max-w-xl py-16 text-center sm:py-24">
      <h1 className="text-3xl sm:text-4xl">Something went wrong on our end</h1>

      <p className="mx-auto mt-4 max-w-prose text-ink/65">
        We could not load this page. Try again, and if it keeps happening let a leader know.
      </p>

      {error?.digest && (
        <p className="nums mt-3 text-xs text-ink/40">Reference: {error.digest}</p>
      )}

      <div className="mt-9 flex flex-wrap items-center justify-center gap-x-4 gap-y-3">
        <button type="button" onClick={() => reset()} className="btn-primary">Try again</button>
        <Link href="/" className="btn-quiet">Back to home</Link>
      </div>
    </section>
  );
}
