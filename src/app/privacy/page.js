import Link from 'next/link';

export const metadata = {
  title: 'Privacy',
  description: 'What Amazing Church Philippines collects, why, and how to have it removed.',
};

const UPDATED = 'September 2026';

export default function PrivacyPage() {
  return (
    <article className="mx-auto max-w-prose py-10">
      <Link href="/" className="btn-quiet -ml-2 mb-8">Back to home</Link>

      <h1 className="text-4xl">Privacy</h1>
      <p className="nums mt-2 text-sm text-ink/50">Last updated {UPDATED}</p>

      <div className="mt-10 space-y-8 leading-relaxed text-ink/75">
        <section>
          <h2 className="text-xl text-ink">What we collect</h2>
          <p className="mt-2">
            When you sign up we store your name, email address, and anything you choose to add to your
            profile, such as a photo. When you post, comment, or react, we store that content along with
            the time it was posted.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Why we collect it</h2>
          <p className="mt-2">
            We use it to run the community: to show your posts to other members, to notify you when
            someone replies, and to let church leaders approve new accounts. We do not sell member
            information, and we do not use it for advertising.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Who can see your posts</h2>
          <p className="mt-2">
            The feed, discussions, and courses are visible to approved members only. Events, news, and
            livestreams are public. Church leaders and moderators can see all member content so they can
            keep the space safe.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Where it is stored</h2>
          <p className="mt-2">
            Member accounts and posts are stored with Supabase. Livestream video is hosted on Facebook,
            and viewing it is covered by Facebook policies rather than ours.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Removing your information</h2>
          <p className="mt-2">
            You can edit or delete your own posts at any time. To close your account and have your
            content removed, contact a church leader and we will action it. Some records may be kept
            where we are required to.
          </p>
        </section>

        <section>
          <h2 className="text-xl text-ink">Questions</h2>
          <p className="mt-2">
            Speak to any of our <Link href="/leaders" className="text-brand underline underline-offset-4">leaders</Link>,
            or raise it after a Sunday service.
          </p>
        </section>
      </div>
    </article>
  );
}
