import { NextResponse } from 'next/server';
import { getSessionAndProfile } from '@/lib/supabase-server';
import { writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

// Files land in ./public/uploads/<userId>/<timestamp>.<ext> so Next.js serves
// them as static assets at /uploads/<userId>/<file>. Nothing hits Supabase Storage.
export const runtime = 'nodejs';

const MAX_BYTES = 50 * 1024 * 1024; // 50 MB

export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user || profile?.account_status !== 'approved')
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const file = form.get('file');
  if (!file || typeof file === 'string')
    return NextResponse.json({ error: 'no file' }, { status: 400 });

  const type = file.type || '';
  if (!(type.startsWith('image/') || type.startsWith('video/')))
    return NextResponse.json({ error: 'only images and videos are allowed' }, { status: 400 });

  if (file.size > MAX_BYTES)
    return NextResponse.json({ error: 'file too large (max 50 MB)' }, { status: 400 });

  const rawExt = (file.name?.split('.').pop() || 'bin').toLowerCase();
  const ext = rawExt.replace(/[^a-z0-9]/g, '').slice(0, 8) || 'bin';
  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  const dir = path.join(process.cwd(), 'public', 'uploads', user.id);
  await mkdir(dir, { recursive: true });
  const filename = `${stamp}.${ext}`;
  await writeFile(path.join(dir, filename), Buffer.from(await file.arrayBuffer()));

  return NextResponse.json({ url: `/uploads/${user.id}/${filename}` });
}
