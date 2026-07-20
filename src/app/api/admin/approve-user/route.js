import { NextResponse } from 'next/server';
import { createClient, createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = form.get('id');
  const action = form.get('action') || 'approve';
  const status = action === 'reject' ? 'rejected' : 'approved';

  const admin = createAdminClient();
  await admin.from('profiles').update({ account_status: status }).eq('id', id);
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
