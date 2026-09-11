'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { AGREEMENT_VERSION, AGREEMENT_POINTS } from '@/lib/agreement';

export default function Signup() {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('');
  const [leaderId, setLeaderId] = useState('');
  const [leaders, setLeaders] = useState([]);
  const [leadersFailed, setLeadersFailed] = useState(false);
  const [accepted, setAccepted] = useState(false);
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
    e.preventDefault(); setError('');

    // Belt and braces: the button is disabled until this is ticked, but a
    // disabled button is a hint, not a control.
    if (!accepted) {
      setError('Please read and accept the agreement before creating an account.');
      return;
    }
    setLoading(true);
    const supabase = createClient();
    const { error: signUpError } = await supabase.auth.signUp({
      email, password,
      options: {
        data: {
          full_name: fullName,
          contact_number: phone.trim(),
          // Validated server-side by the trigger. An empty string means the
          // member did not choose, which is what alerts the leaders.
          leader_id: leaderId || null,
          // Recorded on the profile by the signup trigger, so there is a record
          // of who accepted which version and when.
          terms_accepted_version: AGREEMENT_VERSION,
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

        <div>
          <label className="label" htmlFor="phone">Mobile number</label>
          <input
            id="phone"
            className="input nums"
            type="tel"
            inputMode="tel"
            autoComplete="tel"
            required
            placeholder="+63 917 555 0142"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
          <p className="mt-1 text-xs text-ink/45">
            So a leader can reach you. Only you, your leader, and church staff can see it.
          </p>
        </div>

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

        {/* The agreement, in full, before the tick box. Nobody can honestly
            accept something they were only given a link to. */}
        <section className="rounded-xl bg-paper p-4 ring-1 ring-silver-light">
          <h2 className="text-sm font-semibold text-ink">How we use your information</h2>
          <ul className="mt-2 space-y-1.5 text-sm text-ink/70">
            {AGREEMENT_POINTS.map((point) => (
              <li key={point} className="flex gap-2">
                <span aria-hidden="true" className="mt-2 h-1 w-1 shrink-0 rounded-full bg-gilt" />
                <span>{point}</span>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-xs text-ink/50">
            The full text is in our{' '}
            <Link href="/privacy" className="text-brand underline underline-offset-4">privacy</Link>
            {' '}and{' '}
            <Link href="/terms" className="text-brand underline underline-offset-4">terms</Link> pages.
          </p>

          <label className="mt-4 flex items-start gap-2.5 text-sm">
            <input
              type="checkbox"
              required
              className="mt-0.5 h-4 w-4 shrink-0 accent-brand"
              checked={accepted}
              onChange={(e) => setAccepted(e.target.checked)}
            />
            <span>I have read and agree to how my information is used.</span>
          </label>
        </section>

        {error && <p className="field-error text-sm">{error}</p>}

        <button disabled={loading || !accepted} className="btn-primary w-full">
          {loading ? 'Creating…' : 'Create account'}
        </button>
      </form>

      <p className="text-sm mt-4 text-center text-ink/60">
        Already registered? <Link href="/login" className="text-brand font-medium">Sign in</Link>
      </p>
    </div>
  );
}
