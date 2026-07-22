import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const id = (await req.formData()).get('id')?.toString();
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
  await createAdminClient().from('news_posts').delete().eq('id', id);
  return NextResponse.redirect(new URL('/admin/news', req.url), { status: 303 });
}
