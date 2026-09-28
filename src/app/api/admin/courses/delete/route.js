import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

// Lessons and enrollments cascade; courses that listed this one as a
// prerequisite have it cleared (courses_prereq_id_fkey is ON DELETE SET NULL).
export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isStaff(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const f = await req.formData();
  const id = f.get('id')?.toString();
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
  const { error } = await createAdminClient().from('courses').delete().eq('id', id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  // Only ever return to one of the two pages that show the button.
  const back = f.get('back') === '/admin/courses' ? '/admin/courses' : '/courses';
  return NextResponse.redirect(new URL(back, req.url), { status: 303 });
}
