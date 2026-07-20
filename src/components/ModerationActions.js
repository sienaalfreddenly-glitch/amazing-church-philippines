'use client';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

export default function ModerationActions({ kind, id, status }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const table = kind === 'discussion' ? 'discussions' : 'posts';

  async function setStatus(next) {
    setBusy(true);
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    await supabase.from(table).update({
      status: next, moderated_by: user.id, moderated_at: new Date().toISOString(),
    }).eq('id', id);
    setBusy(false); router.refresh();
  }

  async function del() {
    if (!confirm('Delete this ' + kind + '?')) return;
    setBusy(true);
    await createClient().from(table).delete().eq('id', id);
    setBusy(false); router.refresh();
  }

  return (
    <div className="flex gap-2 mt-3">
      {status !== 'approved' &&
        <button disabled={busy} onClick={()=>setStatus('approved')} className="btn-primary text-xs px-3 py-1">Approve</button>}
      {status !== 'rejected' &&
        <button disabled={busy} onClick={()=>setStatus('rejected')} className="btn-outline text-xs px-3 py-1">Disapprove</button>}
      <button disabled={busy} onClick={del} className="btn-danger text-xs px-3 py-1">Delete</button>
    </div>
  );
}
