'use client';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';

export default function LogoutButton() {
  const router = useRouter();
  return (
    <button
      onClick={async () => {
        await createClient().auth.signOut();
        router.push('/'); router.refresh();
      }}
      className="btn-outline">Log out</button>
  );
}
