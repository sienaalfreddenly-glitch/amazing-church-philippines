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

  // Some rows on other tables carry FKs to profiles without a cascade
  // (e.g. notifications.actor_id, posts.moderated_by), so wipe the ones
  // the app owns first, then delete the auth user (which cascades to
  // profiles). Anything the caller does not have permission to touch
  // through the service-role client is a genuine problem worth reporting
  // rather than swallowing.
  try {
    await admin.from('notifications').delete().or(`user_id.eq.${id},actor_id.eq.${id}`);
    await admin.from('reactions').delete().eq('user_id', id).throwOnError().catch(() => null);
    await admin.from('posts').update({ moderated_by: null }).eq('moderated_by', id);
    await admin.from('discussions').update({ moderated_by: null }).eq('moderated_by', id);
    await admin.from('comments').update({ moderated_by: null }).eq('moderated_by', id).throwOnError().catch(() => null);
    await admin.from('profiles').update({ leader_id: null }).eq('leader_id', id);
    const { error: authError } = await admin.auth.admin.deleteUser(id);
    if (authError) {
      return NextResponse.json({ error: authError.message }, { status: 400 });
    }
  } catch (e) {
    return NextResponse.json({ error: e?.message || 'delete failed' }, { status: 400 });
  }
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
