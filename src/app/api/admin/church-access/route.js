import { NextResponse } from 'next/server';
import { revalidatePath } from 'next/cache';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';

// Super-admin-only toggle for whether a specific admin/moderator may post,
// comment, or start discussions as the church. The RPC re-verifies the
// caller's role.
export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user || profile?.role !== 'super_admin') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }
  const form = await req.formData();
  const id  = String(form.get('id')  || '');
  const can = String(form.get('can') || 'false') === 'true';
  const supabase = createClient();
  const { error } = await supabase.rpc('set_church_posting_access', {
    p_user: id, p_can: can,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  revalidatePath('/admin/church');
  revalidatePath('/admin/users');
  return NextResponse.redirect(new URL('/admin/church', req.url), { status: 303 });
}
