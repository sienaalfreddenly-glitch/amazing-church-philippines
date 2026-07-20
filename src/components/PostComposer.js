'use client';
import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase-browser';
import { useRouter } from 'next/navigation';
import Avatar from './Avatar';
import { IconPhoto } from './Icons';
import MentionInput from './MentionInput';

export default function PostComposer({ kind = 'post' }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [profile, setProfile] = useState(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [mediaUrl, setMediaUrl] = useState('');
  const [msg, setMsg] = useState('');
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [preview, setPreview] = useState(null); // { url, type }
  const [mentions, setMentions] = useState([]);

  useEffect(() => { (async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    const { data } = await supabase.from('profiles').select('*').eq('id', user.id).single();
    setProfile(data);
  })(); }, [supabase]);

  async function uploadFile(e) {
    setMsg('');
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 50 * 1024 * 1024) { setMsg('File must be under 50 MB.'); return; }
    setUploading(true);
    const fd = new FormData();
    fd.append('file', file);
    const res = await fetch('/api/upload', { method: 'POST', body: fd });
    setUploading(false);
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: 'Upload failed.' }));
      return setMsg(err.error || 'Upload failed.');
    }
    const { url } = await res.json();
    setMediaUrl(url);
    setPreview({ url, type: file.type });
  }

  function clearMedia() { setMediaUrl(''); setPreview(null); }

  async function submit(e) {
    e.preventDefault(); setMsg(''); setLoading(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setMsg('Please sign in.'); setLoading(false); return; }
    const table = kind === 'discussion' ? 'discussions' : 'posts';
    const payload = kind === 'discussion'
      ? { author_id: user.id, title, body, mentions }
      : { author_id: user.id, title: title || null, body, media_url: mediaUrl || null, mentions };
    const { error } = await supabase.from(table).insert(payload);
    setLoading(false);
    if (error) return setMsg(error.message);
    setTitle(''); setBody(''); setMediaUrl(''); setPreview(null); setMentions([]); setOpen(false);
    setMsg(kind === 'discussion'
      ? 'Submitted! Your discussion is pending approval.'
      : 'Post shared with the community!');
    router.refresh();
  }

  if (!profile) return null;
  const placeholder = kind === 'discussion'
    ? `Start a discussion, ${profile.full_name.split(' ')[0]}…`
    : `What's on your heart, ${profile.full_name.split(' ')[0]}?`;

  return (
    <div className="card">
      {!open ? (
        <button onClick={() => setOpen(true)}
          className="w-full flex items-center gap-3 text-left">
          <Avatar url={profile.avatar_url} name={profile.full_name} size={44} />
          <span className="flex-1 rounded-full bg-silver-light/60 hover:bg-silver-light px-5 py-3 text-ink/60 transition">
            {placeholder}
          </span>
          <span className="hidden sm:inline text-brand"><IconPhoto size={24} /></span>
        </button>
      ) : (
        <form onSubmit={submit} className="space-y-3">
          <div className="flex items-center gap-3">
            <Avatar url={profile.avatar_url} name={profile.full_name} size={44} />
            <div className="flex-1">
              <p className="text-sm font-medium">{profile.full_name}</p>
              <p className="text-xs text-ink/60">
                {kind === 'discussion' ? 'New discussion · will be reviewed by staff' : 'New post'}
              </p>
            </div>
            <button type="button" onClick={() => setOpen(false)}
              className="text-ink/50 hover:text-ink text-xl leading-none">×</button>
          </div>

          <input className="input" placeholder={kind === 'discussion' ? 'Discussion title' : 'Title (optional)'}
            value={title} onChange={e => setTitle(e.target.value)}
            required={kind === 'discussion'} />

          <MentionInput value={body} onChange={setBody}
            mentions={mentions} onMentionsChange={setMentions}
            placeholder={placeholder + ' (type @ to mention someone)'}
            className="input min-h-[120px] text-base"
            minRows={4} required autoFocus />

          {kind === 'post' && (
            <div className="space-y-2">
              {preview && (
                <div className="relative rounded-xl overflow-hidden border border-silver-light">
                  {preview.type.startsWith('video/')
                    ? <video src={preview.url} controls className="w-full max-h-72 bg-black" />
                    : <img src={preview.url} alt="" className="w-full max-h-72 object-cover" />}
                  <button type="button" onClick={clearMedia}
                    className="absolute top-2 right-2 bg-white/90 hover:bg-white text-ink rounded-full w-7 h-7 shadow-soft"
                    title="Remove">×</button>
                </div>
              )}
              <div className="flex flex-wrap gap-2 items-center">
                <label className="btn-outline cursor-pointer">
                  {uploading ? 'Uploading…' : '📷 Upload photo or video'}
                  <input type="file" accept="image/*,video/*" className="hidden"
                    onChange={uploadFile} disabled={uploading} />
                </label>
                <span className="text-xs text-ink/50">or</span>
                <input className="input flex-1 min-w-[14rem]" placeholder="Paste an image / video URL"
                  value={mediaUrl && !preview ? mediaUrl : ''}
                  onChange={e => { setMediaUrl(e.target.value); setPreview(null); }} />
              </div>
            </div>
          )}

          {msg && <p className="text-sm text-brand">{msg}</p>}
          <div className="flex justify-end gap-2">
            <button type="button" onClick={() => setOpen(false)}
              className="btn-outline">Cancel</button>
            <button disabled={loading} className="btn-primary">
              {loading ? 'Sharing…' : kind === 'discussion' ? 'Submit for approval' : 'Share post'}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
