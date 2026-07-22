import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const f = await req.formData();
  const id = f.get('id')?.toString() || null;
  const image_url = (f.get('image_url') || '').toString().trim();
  const caption = (f.get('caption') || '').toString().trim() || null;
  const ord = parseInt(f.get('ord') || '1', 10) || 1;
  const is_active = f.getAll('is_active').includes('true');
  if (!image_url) return NextResponse.json({ error: 'image_url required' }, { status: 400 });

  const admin = createAdminClient();
  const payload = { image_url, caption, ord, is_active };
  if (id) await admin.from('hero_slides').update(payload).eq('id', id);
  else await admin.from('hero_slides').insert(payload);
  return NextResponse.redirect(new URL('/admin/hero-slides', req.url), { status: 303 });
}
