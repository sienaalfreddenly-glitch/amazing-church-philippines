'use client';
import { useState } from 'react';

export default function HeroSlideForm({ slide, nextOrd = 1 }) {
  const s = slide || {};
  const [uploading, setUploading] = useState(false);
  const [imgUrl, setImgUrl] = useState(s.image_url || '');
  const [err, setErr] = useState('');

  async function pick(e) {
    const file = e.target.files?.[0]; if (!file) return;
    if (file.size > 50 * 1024 * 1024) { setErr('Max 50 MB.'); return; }
    setUploading(true); setErr('');
    const fd = new FormData(); fd.append('file', file);
    const res = await fetch('/api/upload', { method: 'POST', body: fd });
    setUploading(false);
    if (!res.ok) return setErr('Upload failed.');
    const { url } = await res.json();
    setImgUrl(url);
    e.target.value = '';
  }

  return (
    <form action="/api/admin/hero-slides/upsert" method="post" className="mt-3 space-y-3">
      {s.id && <input type="hidden" name="id" value={s.id} />}
      <input type="hidden" name="image_url" value={imgUrl} />
      <div>
        <label className="label">Image</label>
        {imgUrl && (
          <div className="mb-2 rounded-lg overflow-hidden border border-silver-light">
            <img src={imgUrl} alt="" className="w-full max-h-52 object-cover" />
          </div>
        )}
        <label className="btn-outline inline-flex cursor-pointer">
          {uploading ? 'Uploading…' : imgUrl ? 'Replace image' : '📷 Upload image'}
          <input type="file" accept="image/*" className="hidden" onChange={pick} disabled={uploading} />
        </label>
        {err && <p className="text-xs text-red-700 mt-1">{err}</p>}
      </div>
      <div className="grid sm:grid-cols-[6rem_1fr] gap-3">
        <div>
          <label className="label">Order</label>
          <input className="input" name="ord" type="number" min="1" defaultValue={s.ord ?? nextOrd} />
        </div>
        <div>
          <label className="label">Caption (optional)</label>
          <input className="input" name="caption" defaultValue={s.caption || ''} placeholder="Short description" />
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="is_active" value="true" defaultChecked={s.is_active !== false} />
        <span>Active (visible on the home page)</span>
      </label>
      <div className="flex justify-end">
        <button className="btn-primary" disabled={!imgUrl}>{s.id ? 'Save' : 'Add slide'}</button>
      </div>
    </form>
  );
}
