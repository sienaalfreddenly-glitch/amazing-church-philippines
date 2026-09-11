import Link from 'next/link';

export const metadata = {
  title: 'Terms',
  description: 'House rules for members of the Amazing Church Philippines community.',
};

const UPDATED = 'September 2026';

export default function TermsPage() {
  return (
    <article className="mx-auto max-w-prose py-10">
      <Link href="/" className="btn-quiet -ml-2 mb-8">Back to home</Link>

      <h1 className="text-4xl">Terms</h1>
      <p className="nums mt-2 text-sm text-ink/50">Last updated {UPDATED}</p>

      <div className="mt-10 space-y-8 leading-relaxed text-ink/75">
        <section>
          <h2 className="text-xl text-ink">Membership</h2>
          <p className="mt-2">
            Accounts are approved by church leaders before they can post. Keep one account, use your real
            name, and do not share your password. We may pause an account while we look into a concern.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">How we treat each other</h2>
          <p className="mt-2">
            Disagree openly and kindly. Harassment, slurs, threats, and sexual content are not welcome
            here and will be removed. Do not post other people’s private information, and do not share
            what is said in a pastoral conversation.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">What you post</h2>
          <p className="mt-2">
            You keep ownership of what you write and the photos you upload. By posting, you allow the
            church to display that content inside the community and, for anything posted publicly, on our
            public pages. Post only what you have the right to share.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Money and requests</h2>
          <p className="mt-2">
            Do not use the feed or discussions to solicit money, sell goods, or promote a business.
            Giving to the church is handled through the channels announced in service, never through a
            link posted by another member.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Moderation</h2>
          <p className="mt-2">
            Moderators can hide or delete posts and comments that break these terms, and can remove
            accounts for repeated or serious breaches. If you think a decision was wrong, ask a leader to
            review it.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Changes</h2>
          <p className="mt-2">
            We will update these terms as the community grows, and will note the date at the top when we
            do. See also our{' '}
            <Link href="/privacy" className="text-brand underline underline-offset-4">privacy page</Link>.
          </p>
        </section>
      </div>
    </article>
  );
}
