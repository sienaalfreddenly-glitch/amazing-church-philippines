'use client';
import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import Avatar from '@/components/Avatar';

/**
 * Choose whose posts stop reaching your notification bell.
 *
 * Private by construction. The mutes table has exactly one policy, matching
 * rows to the person who created them, with no exception for staff. The person
 * you mute cannot see it, leaders cannot see it, and neither can an admin.
 *
 * Muting only silences the bell. It does not hide anyone's posts from the feed,
 * because this is a church and quietly disappearing people from each other's
 * view would be a different and worse feature.
 */
export default function NotificationMutes({ myId }) {
  const supabase = useMemo(() => createClient(), []);
  const [people, setPeople] = useState([]);
  const [muted, setMuted] = useState(new Set());
  const [query, setQuery] = useState('');
  const [busyId, setBusyId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => { (async () => {
    const [{ data: profiles }, { data: mutes }] = await Promise.all([
      supabase
        .from('profiles')
        .select('id, full_name, avatar_url, title')
        .eq('account_status', 'approved')
        .eq('is_hidden', false)
        .neq('id', myId)
        .order('full_name'),
      supabase.from('notification_mutes').select('muted_id'),
    ]);
    setPeople(profiles || []);
    setMuted(new Set((mutes || []).map((m) => m.muted_id)));
    setLoading(false);
  })(); }, [supabase, myId]);

  async function toggle(personId) {
    setError(''); setBusyId(personId);
    const isMuted = muted.has(personId);

    const { error: opError } = isMuted
      ? await supabase.from('notification_mutes').delete().eq('muted_id', personId)
      : await supabase.from('notification_mutes').insert({ muter_id: myId, muted_id: personId });

    setBusyId(null);
    if (opError && opError.code !== '23505') {
      setError('We could not save that. Please try again.');
      return;
    }

    const next = new Set(muted);
    if (isMuted) next.delete(personId); else next.add(personId);
    setMuted(next);
  }

  const shown = query.trim()
    ? people.filter((p) => p.full_name.toLowerCase().includes(query.trim().toLowerCase()))
    : people;

  if (loading) {
    return (
      <div aria-busy="true" className="space-y-2">
        <span className="sr-only">Loading members</span>
        {[0, 1, 2].map((i) => <div key={i} className="skeleton h-14 w-full" />)}
      </div>
    );
  }

  return (
    <div>
      <p className="text-sm text-ink/60">
        Turn someone off and their posts stop reaching your notifications. They are not told,
        and no leader or admin can see this list.
      </p>

      {people.length > 8 && (
        <input
          type="search"
          className="input mt-4"
          placeholder="Search members"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Search members"
        />
      )}

      {muted.size > 0 && (
        <p className="nums mt-3 text-xs font-medium text-brand">
          {muted.size} {muted.size === 1 ? 'person' : 'people'} muted
        </p>
      )}

      {error && <p className="field-error">{error}</p>}

      <ul className="mt-4 divide-y divide-silver-light">
        {shown.map((person) => {
          const isMuted = muted.has(person.id);
          return (
            <li key={person.id} className="flex items-center gap-3 py-3">
              <Avatar url={person.avatar_url} name={person.full_name} size={36} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{person.full_name}</p>
                {person.title && <p className="truncate text-xs text-ink/50">{person.title}</p>}
              </div>
              <button
                type="button"
                onClick={() => toggle(person.id)}
                disabled={busyId === person.id}
                aria-pressed={isMuted}
                className={isMuted ? 'btn-outline shrink-0' : 'btn-quiet shrink-0'}
              >
                {busyId === person.id ? 'Saving…' : isMuted ? 'Muted' : 'Mute'}
              </button>
            </li>
          );
        })}
      </ul>

      {!shown.length && (
        <p className="py-6 text-center text-sm text-ink/50">Nobody matches that search.</p>
      )}
    </div>
  );
}
