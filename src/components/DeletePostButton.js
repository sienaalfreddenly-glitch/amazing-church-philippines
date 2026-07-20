'use client';
import { useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';

// Deletes a post or discussion. RLS on the server enforces that only the author
// or staff (super_admin / admin / moderator) can actually delete.
export default function DeletePostButton({ id, kind }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const table = kind === 'discussion' ? 'discussions' : 'posts';
  const label = kind === 'discussion' ? 'discussion' : 'post';

  async function del() {
    if (!confirm(`Delete this ${label}? This can't be undone.`)) return;
    setBusy(true);
    const { error } = await createClient().from(table).delete().eq('id', id);
    setBusy(false);
    if (error) { alert('Could not delete: ' + error.message); return; }
    router.refresh();
  }

  return (
    <button onClick={del} disabled={busy}
      title={`Delete this ${label}`}
      className="text-xs text-ink/50 hover:text-red-700 transition-colors px-2 py-1 rounded hover:bg-red-50">
      {busy ? 'Deleting…' : 'Delete'}
    </button>
  );
}
