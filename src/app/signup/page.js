'use client';
import { useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function Signup() {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function submit(e) {
    e.preventDefault(); setError(''); setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signUp({
      email, password,
      options: { data: { full_name: fullName } },
    });
    setLoading(false);
    if (error) return setError(error.message);
    router.push('/pending');
  }

  return (
    <div className="max-w-md mx-auto card mt-10">
      <h1 className="text-2xl mb-1">Join the community</h1>
      <p className="text-sm text-ink/60 mb-6">Accounts are approved by an admin before you can post.</p>
      <form onSubmit={submit} className="space-y-4">
        <div><label className="label">Full name</label>
          <input className="input" value={fullName} onChange={e=>setFullName(e.target.value)} required /></div>
        <div><label className="label">Email</label>
          <input className="input" type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></div>
        <div><label className="label">Password</label>
          <input className="input" type="password" minLength={8} value={password} onChange={e=>setPassword(e.target.value)} required /></div>
        {error && <p className="text-sm text-red-700">{error}</p>}
        <button disabled={loading} className="btn-primary w-full">{loading ? 'Creating…' : 'Create account'}</button>
      </form>
      <p className="text-sm mt-4 text-center text-ink/60">
        Already registered? <Link href="/login" className="text-brand font-medium">Sign in</Link>
      </p>
    </div>
  );
}
