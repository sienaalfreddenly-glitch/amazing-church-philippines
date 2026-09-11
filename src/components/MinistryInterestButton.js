'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase-browser';
import { IconArrow } from '@/components/Icons';

/**
 * Puts a member's hand up for a ministry, and lets them take it down again.
 *
 * Withdrawing matters. Volunteering is a commitment, and a button that cannot
 * be undone makes people hesitate before pressing it. The leader is notified by
 * a database trigger on insert, not from here, so the alert cannot be skipped
 * by calling the API directly.
 */
export default function MinistryInterestButton({ ministryId, ministryName, initiallyInterested }) {
  const router = useRouter();
  const [interested, setInterested] = useState(initiallyInterested);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function toggle() {
    setError(''); setBusy(true);
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      setBusy(false);
      router.push('/login');
      return;
    }

    if (interested) {
      const { error: delError } = await supabase
        .from('ministry_interests')
        .delete()
        .eq('ministry_id', ministryId)
        .eq('profile_id', user.id);
      setBusy(false);
      if (delError) return setError('We could not update that. Please try again.');
      setInterested(false);
    } else {
      const { error: insError } = await supabase
        .from('ministry_interests')
        .insert({ ministry_id: ministryId, profile_id: user.id });
      setBusy(false);
      // Already recorded, from another tab or a double press.
      if (insError && insError.code !== '23505') {
        return setError('We could not update that. Please try again.');
      }
      setInterested(true);
    }
    router.refresh();
  }

  return (
    <div className="card-foot">
      <button
        type="button"
        onClick={toggle}
        disabled={busy}
        aria-pressed={interested}
        className={interested ? 'btn-outline group' : 'btn-primary group'}
      >
        <span>
          {busy
            ? 'Saving…'
            : interested
              ? 'Interested — withdraw'
              : "I'm interested"}
        </span>
        {!interested && !busy && (
          <IconArrow size={15} className="transition-transform duration-200 group-hover:translate-x-1" />
        )}
      </button>

      {interested && !busy && (
        <p className="mt-2 text-xs text-ink/55">
          A leader of {ministryName} has been told and will speak with you.
        </p>
      )}

      {error && <p className="field-error">{error}</p>}
    </div>
  );
}
