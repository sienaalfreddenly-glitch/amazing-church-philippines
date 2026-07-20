import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const form = await req.formData();
  const id = form.get('id');
  const is_active = form.get('is_active') === 'true';
  await createAdminClient().from('courses').update({ is_active }).eq('id', id);
  return NextResponse.redirect(new URL('/admin/courses', req.url), { status: 303 });
}
