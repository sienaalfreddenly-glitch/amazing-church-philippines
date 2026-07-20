import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = form.get('id');
  const leaderRaw = form.get('leader_id');
  const leader_id = leaderRaw && leaderRaw !== '' ? leaderRaw : null;

  if (leader_id === id) return NextResponse.json({ error: 'user cannot lead themselves' }, { status: 400 });

  await createAdminClient().from('profiles').update({ leader_id }).eq('id', id);
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
