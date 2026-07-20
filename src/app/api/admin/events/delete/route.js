import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isStaff(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const f = await req.formData();
  const id = f.get('id')?.toString();
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
  await createAdminClient().from('events').delete().eq('id', id);
  return NextResponse.redirect(new URL('/admin/events', req.url), { status: 303 });
}
