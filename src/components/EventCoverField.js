'use client';
import { useState } from 'react';

// A pair of inputs for the event cover image: upload a photo and the URL
// autofills, or paste one you already have. The form still submits the URL
// through the plain 'cover_url' field, so the server route needs no change.
export default function EventCoverField({ initialUrl = '' }) {
  const [url, setUrl] = useState(initialUrl);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState('');

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
    const { url: uploaded } = await res.json();
    setUrl(uploaded);
  }

  return (
    <div className="space-y-2">
      {url && (
        <div className="overflow-hidden rounded-xl border border-silver-light">
          {/* Cover preview so an admin sees exactly what will land in the feed. */}
          <img src={url} alt="Event cover" className="w-full max-h-56 object-cover" />
        </div>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <label className="btn-outline cursor-pointer">
          {uploading ? 'Uploading…' : 'Upload a photo'}
          <input type="file" accept="image/*" className="hidden" onChange={upload} disabled={uploading} />
        </label>
        <span className="text-xs text-ink/50">or paste a URL</span>
        <input
          type="text"
          name="cover_url"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="https://…"
          className="input flex-1 min-w-[16rem]"
        />
      </div>
      {msg && <p className="text-xs text-brand">{msg}</p>}
    </div>
  );
}
