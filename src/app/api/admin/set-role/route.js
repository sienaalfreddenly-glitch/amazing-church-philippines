import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = form.get('id');
  const role = form.get('role');
  // Only super_admin can create another super_admin
  if (role === 'super_admin' && profile.role !== 'super_admin')
    return NextResponse.json({ error: 'only super_admin can grant super_admin' }, { status: 403 });

  await createAdminClient().from('profiles').update({ role }).eq('id', id);
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
