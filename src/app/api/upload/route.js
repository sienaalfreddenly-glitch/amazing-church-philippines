import { NextResponse } from 'next/server';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';

// Uploads land in the Supabase 'post-media' bucket at <userId>/<timestamp>.<ext>.
// This runs against the same local Docker Supabase (via ngrok tunnel from Vercel),
// so no Supabase Cloud quota is used.
export const runtime = 'nodejs';

const MAX_BYTES = 50 * 1024 * 1024;

export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user || profile?.account_status !== 'approved') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const form = await req.formData();
  const file = form.get('file');
  if (!file || typeof file === 'string') {
    return NextResponse.json({ error: 'no file' }, { status: 400 });
  }
  const type = file.type || '';
  if (!(type.startsWith('image/') || type.startsWith('video/'))) {
    return NextResponse.json({ error: 'only images and videos are allowed' }, { status: 400 });
  }
  if (file.size > MAX_BYTES) {
    return NextResponse.json({ error: 'file too large (max 50 MB)' }, { status: 400 });
  }

  const rawExt = (file.name?.split('.').pop() || 'bin').toLowerCase();
  const ext = rawExt.replace(/[^a-z0-9]/g, '').slice(0, 8) || 'bin';
  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const path = `${user.id}/${stamp}.${ext}`;

  const supabase = createClient();
  const { error: upErr } = await supabase.storage.from('post-media')
    .upload(path, file, { contentType: type, upsert: false, cacheControl: '3600' });
  if (upErr) return NextResponse.json({ error: upErr.message }, { status: 500 });

  const { data: pub } = supabase.storage.from('post-media').getPublicUrl(path);
  return NextResponse.json({ url: pub.publicUrl });
}
