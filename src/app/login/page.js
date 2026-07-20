'use client';
import { useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();

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
