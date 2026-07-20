import { getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function Pending() {
  const { user, profile } = await getSessionAndProfile();

  // If you're already approved, you don't belong here — go home.
  if (user && profile?.account_status === 'approved') redirect('/');

  return (
    <div className="max-w-lg mx-auto card mt-10 text-center">
      <h1 className="text-2xl mb-2">Waiting for approval</h1>
      <p className="text-ink/70">
        Thank you for signing up! An admin will review your account shortly.
        You'll be able to post and start discussions as soon as you're approved.
      </p>
      {!user && (
        <div className="mt-6">
          <Link href="/login" className="btn-outline">Log in</Link>
        </div>
      )}
    </div>
  );
}
