import Link from 'next/link';

// Shown to non-members (logged-out OR unapproved) on member-only pages.
export default function MembersOnlyGate({ title, description }) {
  return (
    <div className="max-w-lg mx-auto mt-8">
      <div className="card text-center"
        style={{ background: 'linear-gradient(135deg, rgba(122,31,43,0.06), rgba(177,85,100,0.03))' }}>
        <p className="text-brand font-semibold uppercase text-xs tracking-widest">Members only</p>
        <h1 className="font-display text-3xl mt-2">{title}</h1>
        <p className="text-ink/70 mt-3">{description}</p>
        <p className="text-ink/60 text-sm mt-4">
          Sign up to join the community. New accounts are approved by an admin.
        </p>
        <div className="mt-6 flex justify-center gap-3 flex-wrap">
          <Link href="/signup" className="btn-primary">Sign up</Link>
          <Link href="/login" className="btn-outline">Log in</Link>
        </div>
      </div>
    </div>
  );
}
