'use client';
import { useState } from 'react';
import Avatar from './Avatar';

// A small client form that uploads an image to /api/upload (returns a URL)
// and then POSTs the URL + display name to /api/admin/church-profile which
// calls the update_church_profile RPC. Kept as its own component so the
// admin/church page can stay a server component.
export default function ChurchAvatarUploader({ currentUrl, currentName }) {
  const [fullName, setFullName] = useState(currentName || '');
  const [avatarUrl, setAvatarUrl] = useState(currentUrl || '');
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState('');
  const [preview, setPreview] = useState(currentUrl || '');

  async function upload(e) {
    setMsg('');
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setMsg('Please choose an image file.');
      return;
    }
    if (file.size > 50 * 1024 * 1024) {
      setMsg('Image must be under 50 MB.');
      return;
    }
    setUploading(true);
    const fd = new FormData();
    fd.append('file', file);
    const res = await fetch('/api/upload', { method: 'POST', body: fd });
    setUploading(false);
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: 'Upload failed.' }));
      setMsg(err.error || 'Upload failed.');
      return;
    }
    const { url } = await res.json();
    setAvatarUrl(url);
    setPreview(url);
  }

  async function save(e) {
    e.preventDefault();
    setMsg('');
    setSaving(true);
    const fd = new FormData();
    fd.append('full_name', fullName);
    fd.append('avatar_url', avatarUrl);
    const res = await fetch('/api/admin/church-profile', { method: 'POST', body: fd });
    setSaving(false);
    if (!res.ok && res.status !== 303) {
      setMsg('Save failed. Try again.');
      return;
    }
    setMsg('Saved. Reloading…');
    window.location.reload();
  }

  return (
    <form onSubmit={save} className="space-y-4">
      <div className="flex items-center gap-4">
        <Avatar url={preview || avatarUrl} name={fullName || 'Amazing Church Philippines'} size={64} fit="contain" />
        <label className="btn-outline cursor-pointer">
          {uploading ? 'Uploading…' : 'Upload a new photo'}
          <input type="file" accept="image/*" className="hidden" onChange={upload} disabled={uploading} />
        </label>
      </div>

      <div>
        <label className="label" htmlFor="full_name">Display name</label>
        <input
          id="full_name"
          type="text"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          required
          className="input"
        />
      </div>

      <div>
        <label className="label" htmlFor="avatar_url">Avatar URL</label>
        <input
          id="avatar_url"
          type="text"
          value={avatarUrl}
          onChange={(e) => { setAvatarUrl(e.target.value); setPreview(e.target.value); }}
          placeholder="/logo.png or a full https:// URL"
          className="input"
        />
        <p className="mt-1 text-xs text-ink/45">
          Filled in automatically when you upload above. You can also paste a URL you already host.
        </p>
      </div>

      {msg && <p className="text-sm text-brand">{msg}</p>}

      <div className="flex justify-end">
        <button type="submit" disabled={saving || uploading} className="btn-primary">
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    </form>
  );
}
