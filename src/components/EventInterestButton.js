'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase-browser';

/**
 * "I'm coming" on an event.
 *
 * A visitor who presses it is sent to sign up rather than being refused. That
 * is the point of the button: it is the cheapest thing a newcomer can say yes
 * to, and it should lead somewhere rather than stop them.
 *
 * Leaders are told by a database trigger on insert, not from here.
 */
export default function EventInterestButton({ eventId, canRespond, initiallyGoing, count }) {
  const router = useRouter();
  const [going, setGoing] = useState(initiallyGoing);
  const [total, setTotal] = useState(count);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  if (!canRespond) {
    return (
      <div className="card-foot">
        <button
          type="button"
          onClick={() => router.push('/signup')}
          className="btn-primary"
        >
          I&apos;m interested
        </button>
        <p className="mt-2 text-xs text-ink/50">
          Takes a minute to join, then we know to expect you.
        </p>
      </div>
    );
  }

  async function toggle() {
    setError(''); setBusy(true);
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setBusy(false); router.push('/login'); return; }

    if (going) {
      const { error: delError } = await supabase
        .from('event_interests').delete()
        .eq('event_id', eventId).eq('profile_id', user.id);
      setBusy(false);
      if (delError) return setError('We could not update that.');
      setGoing(false);
      setTotal((n) => Math.max(0, n - 1));
    } else {
      const { error: insError } = await supabase
        .from('event_interests')
        .insert({ event_id: eventId, profile_id: user.id });
      setBusy(false);
      if (insError && insError.code !== '23505') return setError('We could not update that.');
      setGoing(true);
      setTotal((n) => n + 1);
    }
    router.refresh();
  }

  return (
    <div className="card-foot">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <button
          type="button"
          onClick={toggle}
          disabled={busy}
          aria-pressed={going}
          className={going ? 'btn-outline' : 'btn-primary'}
        >
          {busy ? 'Saving…' : going ? 'Going — change my mind' : "I'm interested"}
        </button>

        {total > 0 && (
          <p className="nums text-sm text-ink/60">
            {total} {total === 1 ? 'person is' : 'people are'} coming
          </p>
        )}
      </div>
      {error && <p className="field-error">{error}</p>}
    </div>
  );
}
