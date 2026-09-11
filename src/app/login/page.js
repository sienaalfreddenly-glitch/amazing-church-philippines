'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [checking, setChecking] = useState(true);
  const router = useRouter();

  // Someone already signed in should never be shown a sign-in form. Without
  // this the page rendered the form regardless, so the header said you were
  // logged in while the body asked you to log in again.
  useEffect(() => { (async () => {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setChecking(false); return; }
    const { data: profile } = await supabase
      .from('profiles').select('account_status').eq('id', user.id).single();
    router.replace(profile?.account_status === 'approved' ? '/feed' : '/pending');
  })(); }, [router]);

  async function submit(e) {
    e.preventDefault(); setError(''); setLoading(true);
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);
    if (error) return setError(error.message);
    const { data: profile } = await supabase.from('profiles').select('account_status').eq('id', data.user.id).single();
    if (profile?.account_status !== 'approved') { router.push('/pending'); return; }
    router.push('/feed'); router.refresh();
  }

  if (checking) {
    return (
      <div className="max-w-md mx-auto card mt-10" aria-busy="true">
        <span className="sr-only">Checking your session</span>
        <div className="skeleton h-7 w-40" />
        <div className="skeleton mt-3 h-4 w-56" />
        <div className="skeleton mt-8 h-11 w-full" />
        <div className="skeleton mt-4 h-11 w-full" />
        <div className="skeleton mt-6 h-11 w-full rounded-full" />
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto card mt-10">
      <h1 className="text-2xl mb-1">Welcome back</h1>
      <p className="text-sm text-ink/60 mb-6">Sign in to continue.</p>
      <form onSubmit={submit} className="space-y-4">
        <div><label className="label">Email</label>
          <input className="input" type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></div>
        <div><label className="label">Password</label>
          <input className="input" type="password" value={password} onChange={e=>setPassword(e.target.value)} required /></div>
        {error && <p className="text-sm text-red-700">{error}</p>}
        <button disabled={loading} className="btn-primary w-full">{loading ? 'Signing in…' : 'Sign in'}</button>
      </form>
      <p className="text-sm mt-4 text-center text-ink/60">
        New here? <Link href="/signup" className="text-brand font-medium">Create an account</Link>
      </p>
    </div>
  );
}
