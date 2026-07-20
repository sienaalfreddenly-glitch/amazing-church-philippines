import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = (form.get('id') || '').toString();
  const status = (form.get('status') || '').toString();
  if (!['enrolled', 'completed', 'dropped'].includes(status))
    return NextResponse.json({ error: 'invalid status' }, { status: 400 });

  const patch = { status, completed_at: status === 'completed' ? new Date().toISOString() : null };
  await createAdminClient().from('enrollments').update(patch).eq('id', id);
  return NextResponse.redirect(new URL('/admin/courses', req.url), { status: 303 });
}
