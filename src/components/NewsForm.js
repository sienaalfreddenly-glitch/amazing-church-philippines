'use client';
import { useState } from 'react';
import MediaUploader from './MediaUploader';

const dtLocal = (v) => v ? new Date(v).toISOString().slice(0, 16) : '';

export default function NewsForm({ post }) {
  const p = post || {};
  const [mediaUrls, setMediaUrls] = useState((p.media_urls || []).join('\n'));

  return (
    <form action="/api/admin/news/upsert" method="post" className="mt-3 space-y-3">
      {p.id && <input type="hidden" name="id" value={p.id} />}
      <div>
        <label className="label">Title</label>
        <input className="input" name="title" required defaultValue={p.title || ''}
          placeholder="Big announcement, article headline, etc." />
      </div>
      <div>
        <label className="label">Body</label>
        <textarea className="input min-h-[140px]" name="body" required defaultValue={p.body || ''}
          placeholder="Write the article, update, or announcement here." />
      </div>
      <div>
        <label className="label">Photos & videos (uploaded)</label>
        <MediaUploader name="media_urls" value={mediaUrls} onChange={setMediaUrls} />
      </div>
      <div>
        <label className="label">External video URL (optional — YouTube or FB Page)</label>
        <input className="input" name="video_url" defaultValue={p.video_url || ''}
          placeholder="https://youtube.com/… or facebook.com/…/videos/…" />
      </div>
      <div>
        <label className="label">Publish time</label>
        <input className="input" name="published_at" type="datetime-local"
          defaultValue={p.published_at ? dtLocal(p.published_at) : dtLocal(new Date().toISOString())} />
      </div>
      <div className="flex justify-end">
        <button className="btn-primary">{p.id ? 'Save changes' : 'Publish'}</button>
      </div>
    </form>
  );
}
