'use client';
import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import Avatar from './Avatar';
import TimeAgo from './TimeAgo';
import ReactionBar from './ReactionBar';
import MentionInput, { RenderMentions } from './MentionInput';

export default function CommentsSection({ entityType, entityId, initialLimit = 3 }) {
  const supabase = useMemo(() => createClient(), []);
  const [comments, setComments] = useState([]);
  const [me, setMe] = useState(null);
  const [meProfile, setMeProfile] = useState(null);
  const [body, setBody] = useState('');
  const [mentions, setMentions] = useState([]);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    setMe(user?.id || null);
    if (user) {
      const { data: p } = await supabase.from('profiles')
        .select('full_name, avatar_url, account_status, role').eq('id', user.id).single();
      setMeProfile(p);
    }
    await load();
  })(); }, [entityType, entityId]);

  async function load() {
    const { data } = await supabase.from('comments')
      .select('id, body, created_at, author_id, author:profiles!comments_author_id_fkey(full_name, avatar_url)')
      .eq('entity_type', entityType).eq('entity_id', entityId)
      .order('created_at', { ascending: true });
    setComments(data || []);
  }

  async function submit(e) {
    e.preventDefault();
    if (!body.trim()) return;
    setErr(''); setBusy(true);
    const { error } = await supabase.from('comments').insert({
      entity_type: entityType, entity_id: entityId,
      author_id: me, body: body.trim(), mentions,
    });
    setBusy(false);
    if (error) return setErr(error.message);
    setBody(''); setMentions([]); load();
  }

  async function del(id) {
    if (!confirm('Delete this comment?')) return;
    await supabase.from('comments').delete().eq('id', id);
    load();
  }

  const staff = ['super_admin','admin','moderator'].includes(meProfile?.role);
  const canPost = me && meProfile?.account_status === 'approved';
  const shown = expanded ? comments : comments.slice(-initialLimit);
  const hiddenCount = comments.length - shown.length;

  return (
    <div className="space-y-4">
      <h3 className="text-sm font-semibold text-ink/70">Comments · {comments.length}</h3>
      {hiddenCount > 0 && (
        <button onClick={() => setExpanded(true)}
          className="text-sm text-brand font-medium hover:underline">
          View all {comments.length} comments
        </button>
      )}
      {expanded && comments.length > initialLimit && (
        <button onClick={() => setExpanded(false)}
          className="text-sm text-ink/60 hover:underline">
          Show less
        </button>
      )}
      <ul className="space-y-4">
        {shown.map(c => (
          <li key={c.id} className="flex gap-3">
            <Avatar url={c.author?.avatar_url} name={c.author?.full_name || ''} size={36} />
            <div className="flex-1 min-w-0">
              <div className="bg-silver-light/50 rounded-2xl px-3 py-2">
                <p className="text-sm font-medium">{c.author?.full_name || 'Member'}</p>
                <p className="text-sm whitespace-pre-wrap"><RenderMentions body={c.body} /></p>
              </div>
              <div className="mt-1 flex gap-3 text-xs text-ink/50 items-center">
                <TimeAgo date={c.created_at} />
                {(c.author_id === me || staff) &&
                  <button onClick={()=>del(c.id)} className="hover:text-red-700">Delete</button>}
              </div>
              <div className="mt-2">
                <ReactionBar entityType="comment" entityId={c.id} size={18} />
              </div>
            </div>
          </li>
        ))}
        {comments.length === 0 && <li className="text-sm text-ink/50">Be the first to comment.</li>}
      </ul>

      {canPost ? (
        <form onSubmit={submit} className="flex gap-2 items-start">
          <div className="flex-1">
            <MentionInput value={body} onChange={setBody}
              mentions={mentions} onMentionsChange={setMentions}
              placeholder="Write a comment… (type @ to mention)"
              className="input min-h-[60px]" minRows={2} />
          </div>
          <button disabled={busy} className="btn-primary self-start">
            {busy ? 'Posting…' : 'Post'}
          </button>
        </form>
      ) : (
        <p className="text-sm text-ink/60">
          {me ? 'Your account is pending approval before you can comment.' : 'Sign in to leave a comment.'}
        </p>
      )}
      {err && <p className="text-sm text-red-700">{err}</p>}
    </div>
  );
}
