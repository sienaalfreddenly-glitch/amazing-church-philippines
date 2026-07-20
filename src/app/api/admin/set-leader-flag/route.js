import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

// Toggle whether a user is designated a Leader (for the org chart + leader picklist).
// Only Super Admin and Admin can change this.
export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = form.get('id');
  const value = form.get('is_leader') === 'true';

  const admin = createAdminClient();
  // If un-flagging as leader, also clear anyone who currently reports to them
  if (!value) {
    await admin.from('profiles').update({ leader_id: null }).eq('leader_id', id);
  }
  await admin.from('profiles').update({ is_leader: value }).eq('id', id);

  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
