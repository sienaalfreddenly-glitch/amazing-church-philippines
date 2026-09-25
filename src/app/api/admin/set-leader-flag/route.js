import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

// Set the church role for a member: Head Pastor / Pastor / Leader / Member.
//
// The first three are all leaders on the org chart; they differ only in the
// title shown next to their name. Member is the default and does not lead a
// group. When a former leader is stepped down to Member, anyone who reported
// to them is unpinned from that leader so the org chart does not point at a
// leader flag that is no longer set.
// Biblical role labels. "Disciple" is the non-leader default; the first three
// are all leaders on the org chart and differ only in the title beside their
// name.
const CHURCH_ROLES = ['Head Pastor', 'Pastor', 'Leader', 'Disciple'];

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const id = form.get('id');
  const churchRole = String(form.get('church_role') || 'Disciple');
  // Fall back to the legacy is_leader boolean for any caller still submitting
  // the old form; treat true as Leader, false as Disciple.
  const legacyBool = form.get('is_leader');
  let effectiveRole = CHURCH_ROLES.includes(churchRole) ? churchRole
    : legacyBool === 'true' ? 'Leader'
    : legacyBool === 'false' ? 'Disciple'
    : 'Disciple';

  const isLeader = effectiveRole !== 'Disciple';
  const title    = isLeader ? effectiveRole : null;

  const admin = createAdminClient();
  if (!isLeader) {
    await admin.from('profiles').update({ leader_id: null }).eq('leader_id', id);
  }
  await admin.from('profiles').update({ is_leader: isLeader, title }).eq('id', id);

  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
