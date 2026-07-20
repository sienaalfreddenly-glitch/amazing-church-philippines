'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';

export default function ChangePassword() {
  const supabase = createClient();
  const router = useRouter();
  const [pw1, setPw1] = useState('');
  const [pw2, setPw2] = useState('');
  const [required, setRequired] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { router.replace('/login'); return; }
    const { data } = await supabase.from('profiles').select('must_change_password').eq('id', user.id).single();
    setRequired(!!data?.must_change_password);
  })(); }, []);

  async function submit(e) {
    e.preventDefault(); setErr(''); setMsg('');
    if (pw1.length < 8) return setErr('Password must be at least 8 characters.');
    if (pw1 !== pw2)    return setErr('Passwords do not match.');
    setBusy(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.auth.updateUser({ password: pw1 });
    if (error) { setBusy(false); return setErr(error.message); }
    await supabase.from('profiles').update({ must_change_password: false }).eq('id', user.id);
    setBusy(false);
    setMsg('Password updated. Redirecting…');
    setTimeout(() => { router.replace('/'); router.refresh(); }, 900);
  }

  return (
    <div className="max-w-md mx-auto card mt-10">
      <h1 className="text-2xl">Set a new password</h1>
      {required ? (
        <p className="text-sm text-amber-700 mt-1">
          An admin set a temporary password for your account. Please choose your own before continuing.
        </p>
      ) : (
        <p className="text-sm text-ink/60 mt-1">Choose a new password for your account.</p>
      )}
      <form onSubmit={submit} className="mt-5 space-y-4">
        <div>
          <label className="label">New password</label>
          <input className="input" type="password" minLength={8}
            value={pw1} onChange={e => setPw1(e.target.value)} required autoFocus />
        </div>
        <div>
          <label className="label">Confirm new password</label>
          <input className="input" type="password" minLength={8}
            value={pw2} onChange={e => setPw2(e.target.value)} required />
        </div>
        {err && <p className="text-sm text-red-700">{err}</p>}
        {msg && <p className="text-sm text-brand">{msg}</p>}
        <button disabled={busy} className="btn-primary w-full">
          {busy ? 'Updating…' : 'Update password'}
        </button>
      </form>
    </div>
  );
}
