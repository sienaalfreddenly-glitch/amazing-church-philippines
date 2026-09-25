import Link from 'next/link';
import { getContent } from '@/lib/content';

export const metadata = {
  title: 'Terms',
  description: 'House rules for members of the Amazing Church Philippines community.',
};

// Every heading and body is a slug: super admins edit the copy from
// /admin/content and it appears here without a deploy.
const SECTIONS = [
  { headingSlug: 'terms.membership.heading', bodySlug: 'terms.membership.body' },
  { headingSlug: 'terms.conduct.heading',    bodySlug: 'terms.conduct.body'    },
  { headingSlug: 'terms.posts.heading',      bodySlug: 'terms.posts.body'      },
  { headingSlug: 'terms.money.heading',      bodySlug: 'terms.money.body'      },
  { headingSlug: 'terms.moderation.heading', bodySlug: 'terms.moderation.body' },
  { headingSlug: 'terms.changes.heading',    bodySlug: 'terms.changes.body'    },
];

export default async function TermsPage() {
  const updated = await getContent('terms.updated');
  const sections = await Promise.all(
    SECTIONS.map(async (s) => ({
      heading: await getContent(s.headingSlug),
      body:    await getContent(s.bodySlug),
    }))
  );

  return (
    <article className="mx-auto max-w-prose py-10">
      <Link href="/" className="btn-quiet -ml-2 mb-8">Back to home</Link>

      <h1 className="text-4xl">Terms</h1>
      <p className="nums mt-2 text-sm text-ink/50">Last updated {updated}</p>

      <div className="mt-10 space-y-8 leading-relaxed text-ink/75">
        {sections.map((s, i) => (
          <section key={i}>
            <h2 className="text-xl text-ink">{s.heading}</h2>
            <p className="mt-2 whitespace-pre-line">{s.body}</p>
          </section>
        ))}
        <p className="text-sm text-ink/60">
          See also our{' '}
          <Link href="/privacy" className="text-brand underline underline-offset-4">privacy page</Link>.
        </p>
      </div>
    </article>
  );
}
