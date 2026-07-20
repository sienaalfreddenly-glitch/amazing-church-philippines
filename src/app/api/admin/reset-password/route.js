import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const form = await req.formData();
  const id = form.get('id');
  const admin = createAdminClient();
  const { data: target } = await admin.from('profiles').select('email').eq('id', id).single();
  if (!target) return NextResponse.json({ error: 'user not found' }, { status: 404 });
  await admin.auth.resetPasswordForEmail(target.email, {
    redirectTo: new URL('/login', req.url).toString(),
  });
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
