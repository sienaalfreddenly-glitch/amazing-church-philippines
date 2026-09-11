import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const ministry_id = form.get('ministry_id');
  const raw = form.get('leader_id');
  const leader_id = raw && raw !== '' ? raw : null;

  if (!ministry_id) return NextResponse.json({ error: 'ministry_id required' }, { status: 400 });

  const admin = createAdminClient();

  // Only someone already marked as a leader may be put in charge of a ministry.
  // Without this, an admin could hand a ministry to an ordinary member, who
  // would then see the volunteer list without being a leader anywhere else.
  if (leader_id) {
    const { data: candidate } = await admin
      .from('profiles')
      .select('id, is_leader, account_status')
      .eq('id', leader_id)
      .single();

    if (!candidate || !candidate.is_leader || candidate.account_status !== 'approved') {
      return NextResponse.json({ error: 'not an approved leader' }, { status: 400 });
    }
  }

  await admin.from('ministries').update({ leader_id }).eq('id', ministry_id);
  return NextResponse.redirect(new URL('/admin/ministries', req.url), { status: 303 });
}
