import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const user_id = (form.get('user_id') || '').toString();
  const course_id = (form.get('course_id') || '').toString();
  if (!user_id || !course_id) return NextResponse.json({ error: 'missing fields' }, { status: 400 });

  const admin = createAdminClient();

  // Prereq check: if the course requires another course, the member must have completed it.
  const { data: course } = await admin.from('courses').select('prereq_id, code').eq('id', course_id).single();
  if (!course) return NextResponse.json({ error: 'course not found' }, { status: 404 });

  if (course.prereq_id) {
    const { data: done } = await admin.from('enrollments')
      .select('id').eq('user_id', user_id).eq('course_id', course.prereq_id).eq('status', 'completed').maybeSingle();
    if (!done) {
      const { data: pre } = await admin.from('courses').select('code').eq('id', course.prereq_id).single();
      return NextResponse.json(
        { error: `Prerequisite not met: member must complete ${pre?.code || 'the prerequisite'} first.` },
        { status: 400 });
    }
  }

  // Upsert so re-enrolling a dropped member just resets their status
  await admin.from('enrollments').upsert({
    user_id, course_id, status: 'enrolled',
    enrolled_by: profile.id, enrolled_at: new Date().toISOString(), completed_at: null,
  }, { onConflict: 'user_id,course_id' });

  return NextResponse.redirect(new URL('/admin/courses', req.url), { status: 303 });
}
