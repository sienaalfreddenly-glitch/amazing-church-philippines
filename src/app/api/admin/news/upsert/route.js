import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const f = await req.formData();
  const id = f.get('id')?.toString() || null;
  const title = (f.get('title') || '').toString().trim();
  const body = (f.get('body') || '').toString().trim();
  const video_url = (f.get('video_url') || '').toString().trim() || null;
  const media_urls = (f.get('media_urls') || '').toString()
    .split('\n').map(s => s.trim()).filter(Boolean);
  const publishedRaw = f.get('published_at')?.toString();
  const published_at = publishedRaw || new Date().toISOString();
  if (!title || !body) return NextResponse.json({ error: 'title and body required' }, { status: 400 });

  const admin = createAdminClient();
  const payload = { title, body, media_urls, video_url, published_at };
  if (id) await admin.from('news_posts').update(payload).eq('id', id);
  else await admin.from('news_posts').insert({ ...payload, author_id: profile.id });

  return NextResponse.redirect(new URL('/admin/news', req.url), { status: 303 });
}
