import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

// Toggle a member's lesson-verified state.
export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const f = await req.formData();
  const enrollment_id = f.get('enrollment_id')?.toString();
  const lesson_id = f.get('lesson_id')?.toString();
  const course_id = f.get('course_id')?.toString();
  const value = f.get('verified') === 'true';
  if (!enrollment_id || !lesson_id) return NextResponse.json({ error: 'missing fields' }, { status: 400 });

  const admin = createAdminClient();
  if (value) {
    await admin.from('lesson_completions').upsert({
      enrollment_id, lesson_id, verified_by: profile.id, verified_at: new Date().toISOString(),
    }, { onConflict: 'enrollment_id,lesson_id' });
  } else {
    await admin.from('lesson_completions').delete()
      .eq('enrollment_id', enrollment_id).eq('lesson_id', lesson_id);
  }

  // Auto-complete enrollment when every lesson is verified
  const [{ data: lessonRows }, { data: doneRows }] = await Promise.all([
    admin.from('course_lessons').select('id').eq('course_id', course_id),
    admin.from('lesson_completions').select('lesson_id').eq('enrollment_id', enrollment_id),
  ]);
  const total = lessonRows?.length || 0;
  const done = doneRows?.length || 0;
  if (total > 0 && done >= total) {
    await admin.from('enrollments').update({
      status: 'completed', completed_at: new Date().toISOString(),
    }).eq('id', enrollment_id);
  } else {
    await admin.from('enrollments').update({
      status: 'enrolled', completed_at: null,
    }).eq('id', enrollment_id).eq('status', 'completed');
  }

  return NextResponse.redirect(new URL(`/admin/courses/${course_id}`, req.url), { status: 303 });
}
