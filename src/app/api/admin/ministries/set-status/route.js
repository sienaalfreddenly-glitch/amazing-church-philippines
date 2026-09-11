import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

const ALLOWED = new Set(['interested', 'member', 'declined']);

/**
 * Accept a volunteer onto a team, or stand them down.
 *
 * Open to the ministry's own leader as well as to staff, because the person who
 * runs the team is the one who should decide who is on it. The check is done
 * here rather than trusting the form, since the redirect target is guessable.
 */
export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const interest_id = form.get('interest_id');
  const status = form.get('status');
  const role_in_team = (form.get('role_in_team') || '').trim() || null;
  const slug = form.get('slug');

  if (!interest_id || !ALLOWED.has(status)) {
    return NextResponse.json({ error: 'bad request' }, { status: 400 });
  }

  const admin = createAdminClient();

  const { data: row } = await admin
    .from('ministry_interests')
    .select('id, ministry:ministries(id, slug, leader_id)')
    .eq('id', interest_id)
    .single();

  if (!row) return NextResponse.json({ error: 'not found' }, { status: 404 });

  const mayDecide = isStaff(profile?.role) || row.ministry?.leader_id === user.id;
  if (!mayDecide) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  await admin
    .from('ministry_interests')
    .update({
      status,
      role_in_team,
      decided_at: new Date().toISOString(),
      decided_by: user.id,
    })
    .eq('id', interest_id);

  const back = slug || row.ministry?.slug;
  return NextResponse.redirect(new URL(`/ministries/${back}/interested`, req.url), { status: 303 });
}
