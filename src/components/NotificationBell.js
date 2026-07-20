'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import Avatar from './Avatar';
import { IconBell } from './Icons';
import { timeAgo } from '@/lib/format';

const KIND_TEXT = {
  enrolled:        'enrolled you in',
  lesson_verified: 'verified your lesson',
  reaction:        'reacted to your',
  comment:         'commented on your',
  mention:         'mentioned you in a',
};

function linkFor(n) {
  if (n.entity_type === 'post')       return `/posts/${n.entity_id}`;
  if (n.entity_type === 'discussion') return `/discussions/${n.entity_id}`;
  if (n.entity_type === 'course')     return `/courses/${n.entity_id}`;
  if (n.entity_type === 'lesson')     return `/courses`;
  if (n.entity_type === 'comment')    return `/feed`;
  return '#';
}

export default function NotificationBell() {
  const supabase = useMemo(() => createClient(), []);
  const [items, setItems] = useState([]);
  const [open, setOpen] = useState(false);
  const wrap = useRef(null);

  async function load() {
    const { data } = await supabase.from('notifications')
      .select('*, actor:profiles!notifications_actor_id_fkey(full_name, avatar_url)')
      .order('created_at', { ascending: false })
      .limit(15);
    setItems(data || []);
  }

  useEffect(() => {
    load();
    // Realtime: subscribe to new notifications for this user.
    // Use a unique channel name per mount so React StrictMode's double-effect
    // in dev doesn't reuse a still-subscribed channel and error on .on().
    let channel;
    let cancelled = false;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || cancelled) return;
      channel = supabase
        .channel(`notifs-${user.id}-${Math.random().toString(36).slice(2, 8)}`)
        .on('postgres_changes',
          { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${user.id}` },
          () => load());
      if (!cancelled) channel.subscribe();
    })();
    const t = setInterval(load, 60_000);
    function onDoc(e) { if (wrap.current && !wrap.current.contains(e.target)) setOpen(false); }
    document.addEventListener('mousedown', onDoc);
    return () => {
      cancelled = true;
      if (channel) supabase.removeChannel(channel);
      clearInterval(t);
      document.removeEventListener('mousedown', onDoc);
    };
  }, [supabase]);

  const unread = items.filter(n => !n.read_at).length;

  async function markAllRead() {
    if (unread === 0) return;
    await supabase.from('notifications')
      .update({ read_at: new Date().toISOString() })
      .is('read_at', null);
    load();
  }

  async function markOne(id) {
    await supabase.from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('id', id).is('read_at', null);
    load();
  }

  function renderMessage(n) {
    const who = n.actor?.full_name || 'Someone';
    const verb = KIND_TEXT[n.kind] || 'notified you';
    let suffix = '';
    if (n.kind === 'enrolled')        suffix = ` ${n.metadata?.course_code || 'a course'}`;
    else if (n.kind === 'lesson_verified') {
      return `Lesson verified — ${n.metadata?.course_code || ''} ${n.metadata?.lesson_title ? '· ' + n.metadata.lesson_title : ''}`;
    }
    else if (n.kind === 'reaction')   suffix = ` ${n.entity_type}${n.metadata?.emoji ? ' (' + n.metadata.emoji + ')' : ''}`;
    else if (n.kind === 'comment')    suffix = ` ${n.entity_type}`;
    else if (n.kind === 'mention')    suffix = ` ${n.entity_type}`;
    return `${who} ${verb}${suffix}`;
  }

  return (
    <div ref={wrap} className="relative">
      <button onClick={() => setOpen(o => !o)}
        className="relative p-2 rounded-full hover:bg-silver-light/70 transition"
        aria-label="Notifications">
        <span className="text-ink/70"><IconBell size={22} /></span>
        {unread > 0 && (
          <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 flex items-center justify-center rounded-full bg-brand text-white text-[10px] font-bold">
            {unread > 99 ? '99+' : unread}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-80 max-h-[70vh] overflow-auto bg-white rounded-2xl border border-silver-light shadow-lg z-50">
          <div className="sticky top-0 bg-white/95 backdrop-blur px-4 py-2.5 border-b border-silver-light flex items-center justify-between">
            <p className="font-semibold text-sm">Notifications</p>
            {unread > 0 && (
              <button onClick={markAllRead} className="text-xs text-brand hover:underline">Mark all read</button>
            )}
          </div>
          {items.length === 0 ? (
            <p className="text-sm text-ink/60 text-center py-8">You're all caught up.</p>
          ) : (
            <ul>
              {items.map(n => (
                <li key={n.id} className={`border-b border-silver-light/70 last:border-b-0
                  ${!n.read_at ? 'bg-brand-50/40' : ''}`}>
                  <a href={linkFor(n)} onClick={() => markOne(n.id)}
                    className="flex items-start gap-3 px-4 py-3 hover:bg-silver-light/40">
                    <Avatar url={n.actor?.avatar_url} name={n.actor?.full_name || ''} size={34} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm leading-snug">{renderMessage(n)}</p>
                      <p className="text-xs text-ink/50 mt-0.5">{timeAgo(n.created_at)}</p>
                    </div>
                    {!n.read_at && <span className="mt-1 w-2 h-2 rounded-full bg-brand" />}
                  </a>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
