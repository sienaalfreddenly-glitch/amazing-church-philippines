import { NextResponse } from 'next/server';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

// Promote a Disciple to Leader, or a Leader to Pastor.
//
// The database function is the source of truth for who is allowed to do this
// and what the resulting side effects are (post to the feed, notify every
// leader). This route is a thin authenticated wrapper so the check for a
// signed-in staff member happens at the edge before we spend a round trip.
export async function POST(req) {
  const { user, profile } = await getSessionAndProfile();
  if (!user || !isStaff(profile?.role)) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const form = await req.formData();
  const targetId = String(form.get('id') || '');
  const to = String(form.get('to') || '');
  if (!targetId || !['Leader', 'Pastor'].includes(to)) {
    return NextResponse.json({ error: 'bad request' }, { status: 400 });
  }

  // Call as the signed-in user so auth.uid() inside the function matches the
  // actor (RLS and the function's own authorisation check depend on it).
  const supabase = createClient();
  const { error } = await supabase.rpc('promote_member', { p_target: targetId, p_to: to });
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }
  return NextResponse.redirect(new URL('/admin/users', req.url), { status: 303 });
}
