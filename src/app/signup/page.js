'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function Signup() {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [leaderId, setLeaderId] = useState('');
  const [leaders, setLeaders] = useState([]);
  const [leadersFailed, setLeadersFailed] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  // list_leaders() is a security-definer function returning names and ids only,
  // because nobody is signed in yet and RLS would otherwise refuse the read.
  useEffect(() => { (async () => {
    const supabase = createClient();
    const { data, error: rpcError } = await supabase.rpc('list_leaders');
    if (rpcError) { setLeadersFailed(true); return; }
    setLeaders(data || []);
  })(); }, []);

  async function submit(e) {
    e.preventDefault(); setError(''); setLoading(true);
    const supabase = createClient();
    const { error: signUpError } = await supabase.auth.signUp({
      email, password,
      options: {
        data: {
          full_name: fullName,
          // Validated server-side by the trigger. An empty string means the
          // member did not choose, which is what alerts the leaders.
          leader_id: leaderId || null,
        },
      },
    });
    setLoading(false);
    if (signUpError) return setError(signUpError.message);
    router.push('/pending');
  }

  return (
    <div className="max-w-md mx-auto card mt-10">
      <h1 className="text-2xl mb-1">Join the community</h1>
      <p className="text-sm text-ink/60 mb-6">Accounts are approved by an admin before you can post.</p>

      <form onSubmit={submit} className="space-y-4">
        <div><label className="label" htmlFor="name">Full name</label>
          <input id="name" className="input" value={fullName} onChange={e=>setFullName(e.target.value)} required /></div>

        <div><label className="label" htmlFor="email">Email</label>
          <input id="email" className="input" type="email" autoComplete="email"
            value={email} onChange={e=>setEmail(e.target.value)} required /></div>

        <div><label className="label" htmlFor="password">Password</label>
          <input id="password" className="input" type="password" minLength={8} autoComplete="new-password"
            value={password} onChange={e=>setPassword(e.target.value)} required />
          <p className="mt-1 text-xs text-ink/45">At least 8 characters.</p></div>

        {/* Optional on purpose. Leaving it unset is a normal answer for someone
            new who does not know anyone yet, and it alerts the leaders. */}
        <div>
          <label className="label" htmlFor="leader">
            Your leader <span className="font-normal normal-case tracking-normal text-ink/45">· optional</span>
          </label>

          {leadersFailed ? (
            <p className="text-sm text-ink/55">
              We could not load the leader list. You can still sign up, and a leader will reach out.
            </p>
          ) : (
            <>
              <select id="leader" className="input" value={leaderId} onChange={e=>setLeaderId(e.target.value)}>
                <option value="">I do not have one yet</option>
                {leaders.map((l) => (
                  <option key={l.id} value={l.id}>{l.full_name}</option>
                ))}
              </select>
              <p className="mt-1 text-xs text-ink/45">
                {leaderId
                  ? 'They will see you in their group once your account is approved.'
                  : 'Leave this as it is and our leaders will be told, so someone can welcome you.'}
              </p>
            </>
          )}
        </div>

        {error && <p className="field-error text-sm">{error}</p>}

        <button disabled={loading} className="btn-primary w-full">
          {loading ? 'Creating…' : 'Create account'}
        </button>
      </form>

      <p className="text-sm mt-4 text-center text-ink/60">
        Already registered? <Link href="/login" className="text-brand font-medium">Sign in</Link>
      </p>
    </div>
  );
}
