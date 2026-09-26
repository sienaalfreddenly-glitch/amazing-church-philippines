import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const form = await req.formData();
  const id = form.get('id');
  if (id === profile.id) return NextResponse.json({ error: "can't delete yourself" }, { status: 400 });

  const admin = createAdminClient();
  const { data: target } = await admin.from('profiles').select('role').eq('id', id).single();
  if (target?.role === 'super_admin' && profile.role !== 'super_admin')
    return NextResponse.json({ error: 'only super_admin can delete a super_admin' }, { status: 403 });

  // Cascades and SET NULL rules in the schema clean up everything that
  // references the user (see 20260924_profile_fks_set_null.sql).
  const { error } = await admin.auth.admin.deleteUser(id);
  if (error) {
    console.error('delete-user failed:', error);
    return NextResponse.json(
      { error: 'Could not delete this account. Check the auth service logs for the database error.' },
      { status: 500 },
    );
  }
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
