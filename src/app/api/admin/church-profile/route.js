import { NextResponse } from 'next/server';
import { revalidatePath } from 'next/cache';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';

// Super-admin-only update of the church profile via the update_church_profile
// RPC. The RPC re-checks the caller's role, so this route is a thin wrapper
// that only exists to translate the form post into an RPC call.
export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user || profile?.role !== 'super_admin') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const form = await req.formData();
  const fullName  = String(form.get('full_name')  || '');
  const avatarUrl = String(form.get('avatar_url') || '');

  const supabase = createClient();
  const { error } = await supabase.rpc('update_church_profile', {
    p_full_name:  fullName,
    p_avatar_url: avatarUrl,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  revalidatePath('/admin/church');
  revalidatePath('/feed');
  return NextResponse.redirect(new URL('/admin/church', req.url), { status: 303 });
}
