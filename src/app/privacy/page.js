import Link from 'next/link';
import { getContent } from '@/lib/content';

export const metadata = {
  title: 'Privacy',
  description: 'What Amazing Church Philippines collects, why, and how to have it removed.',
};

const SECTIONS = [
  { headingSlug: 'privacy.collect.heading',    bodySlug: 'privacy.collect.body'    },
  { headingSlug: 'privacy.why.heading',        bodySlug: 'privacy.why.body'        },
  { headingSlug: 'privacy.visibility.heading', bodySlug: 'privacy.visibility.body' },
  { headingSlug: 'privacy.storage.heading',    bodySlug: 'privacy.storage.body'    },
  { headingSlug: 'privacy.removal.heading',    bodySlug: 'privacy.removal.body'    },
  { headingSlug: 'privacy.questions.heading',  bodySlug: 'privacy.questions.body'  },
];

export default async function PrivacyPage() {
  const updated = await getContent('privacy.updated');
  const sections = await Promise.all(
    SECTIONS.map(async (s) => ({
      heading: await getContent(s.headingSlug),
      body:    await getContent(s.bodySlug),
    }))
  );

  return (
    <article className="mx-auto max-w-prose py-10">
      <Link href="/" className="btn-quiet -ml-2 mb-8">Back to home</Link>

      <h1 className="text-4xl">Privacy</h1>
      <p className="nums mt-2 text-sm text-ink/50">Last updated {updated}</p>

      <div className="mt-10 space-y-8 leading-relaxed text-ink/75">
        {sections.map((s, i) => (
          <section key={i}>
            <h2 className="text-xl text-ink">{s.heading}</h2>
            <p className="mt-2 whitespace-pre-line">{s.body}</p>
          </section>
        ))}
      </div>
    </article>
  );
}
