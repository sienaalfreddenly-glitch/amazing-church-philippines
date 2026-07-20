'use client';
import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { REACTION_ICONS } from './ReactionIcons';

const CHOICES = [
  { key: 'love',   label: 'Love'   },
  { key: 'pray',   label: 'Pray'   },
  { key: 'amen',   label: 'Amen'   },
  { key: 'bless',  label: 'Bless'  },
  { key: 'praise', label: 'Praise' },
];

export default function ReactionBar({ entityType, entityId, commentCount, size = 22 }) {
  const supabase = useMemo(() => createClient(), []);
  const [reactions, setReactions] = useState([]);
  const [me, setMe] = useState(null);
  const [busy, setBusy] = useState(false);
  const [popKey, setPopKey] = useState(null);

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    setMe(user?.id || null);
    const { data } = await supabase.from('reactions')
      .select('emoji, user_id')
      .eq('entity_type', entityType).eq('entity_id', entityId);
    setReactions(data || []);
  })(); }, [entityType, entityId, supabase]);

  const counts = reactions.reduce((acc, r) => (acc[r.emoji] = (acc[r.emoji]||0)+1, acc), {});
  const mine = new Set(reactions.filter(r => r.user_id === me).map(r => r.emoji));

  async function toggle(key) {
    if (!me || busy) return;
    setBusy(true);
    setPopKey(key + Date.now());
    if (mine.has(key)) {
      await supabase.from('reactions').delete()
        .eq('entity_type', entityType).eq('entity_id', entityId)
        .eq('user_id', me).eq('emoji', key);
      setReactions(reactions.filter(r => !(r.user_id === me && r.emoji === key)));
    } else {
      await supabase.from('reactions').insert({
        entity_type: entityType, entity_id: entityId, user_id: me, emoji: key,
      });
      setReactions([...reactions, { emoji: key, user_id: me }]);
    }
    setBusy(false);
  }

  // Summary of only reactions that have at least one, in choice order
  const summary = CHOICES.filter(c => counts[c.key] > 0);

  return (
    <div className="flex items-center justify-between gap-4 flex-wrap">
      {/* Compact pick bubble */}
      <div className="inline-flex items-center gap-0.5 rounded-full bg-white px-1.5 py-1 shadow-soft border border-silver-light">
        {CHOICES.map(({ key, label }) => {
          const Icon = REACTION_ICONS[key];
          const active = mine.has(key);
          const pop = popKey?.startsWith(key);
          return (
            <button
              key={key}
              onClick={() => toggle(key)}
              disabled={!me || busy}
              title={label}
              aria-label={label}
              className={`p-1 rounded-full transition-all duration-150 active:scale-90
                ${active ? 'ring-2 ring-brand/30 bg-brand-50' : 'hover:bg-silver-light/70 hover:-translate-y-0.5'}
                ${!me ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer'}`}
            >
              <span className={`inline-flex ${pop ? 'animate-pop' : ''}`}>
                <Icon size={size} />
              </span>
            </button>
          );
        })}
        {!me && <span className="text-[10px] text-ink/50 ml-1 pr-1">Sign in</span>}
      </div>

      {/* Per-reaction counts + comment count summary */}
      <div className="flex items-center gap-3 text-xs text-ink/60">
        {summary.length > 0 && (
          <div className="inline-flex items-center gap-2">
            {summary.map(({ key, label }) => {
              const Icon = REACTION_ICONS[key];
              return (
                <span key={key} className="inline-flex items-center gap-1" title={`${counts[key]} ${label}`}>
                  <Icon size={14} />
                  <span className="tabular-nums font-medium text-ink/70">{counts[key]}</span>
                </span>
              );
            })}
          </div>
        )}
        {commentCount != null && (
          <span className="inline-flex items-center gap-1">
            💬 <span className="tabular-nums">{commentCount}</span>
            <span className="hidden sm:inline">{commentCount === 1 ? 'comment' : 'comments'}</span>
          </span>
        )}
      </div>
    </div>
  );
}
