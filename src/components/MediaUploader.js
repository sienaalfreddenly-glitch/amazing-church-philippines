'use client';
import { useState } from 'react';

// A file-upload widget that POSTs to /api/upload (writes to public/uploads/<uid>/)
// and appends the returned URL to a hidden textarea list.
// value = newline-separated list of URLs (matches what the API route expects).
export default function MediaUploader({ name, value, onChange, accept = 'image/*,video/*' }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const urls = value.split('\n').map(s => s.trim()).filter(Boolean);

  async function pick(e) {
    const files = Array.from(e.target.files || []);
    if (!files.length) return;
    setBusy(true); setErr('');
    const added = [];
    for (const file of files) {
      if (file.size > 50 * 1024 * 1024) { setErr(`${file.name}: too big (max 50 MB)`); continue; }
      const fd = new FormData(); fd.append('file', file);
      const res = await fetch('/api/upload', { method: 'POST', body: fd });
      if (!res.ok) { setErr(`${file.name}: upload failed`); continue; }
      const { url } = await res.json();
      added.push(url);
    }
    e.target.value = '';
    onChange([...urls, ...added].join('\n'));
    setBusy(false);
  }

  function remove(u) {
    onChange(urls.filter(x => x !== u).join('\n'));
  }

  return (
    <div className="space-y-2">
      <input type="hidden" name={name} value={value} />
      <label className="btn-outline inline-flex cursor-pointer">
        {busy ? 'Uploading…' : '📷 Add photos / videos'}
        <input type="file" accept={accept} multiple className="hidden" onChange={pick} disabled={busy} />
      </label>
      {err && <p className="text-xs text-red-700">{err}</p>}
      {urls.length > 0 && (
        <ul className="grid grid-cols-3 sm:grid-cols-4 gap-2">
          {urls.map(u => (
            <li key={u} className="relative rounded-lg overflow-hidden border border-silver-light bg-black/5">
              {/\.(mp4|webm|mov)$/i.test(u)
                ? <video src={u} className="w-full h-24 object-cover" />
                : <img src={u} alt="" className="w-full h-24 object-cover" />}
              <button type="button" onClick={() => remove(u)}
                className="absolute top-1 right-1 bg-white/90 hover:bg-white text-ink text-xs rounded-full w-6 h-6 shadow-soft">×</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
