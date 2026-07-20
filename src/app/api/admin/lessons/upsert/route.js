import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const f = await req.formData();
  const id = f.get('id')?.toString() || null;
  const course_id = f.get('course_id')?.toString();
  if (!course_id) return NextResponse.json({ error: 'course_id required' }, { status: 400 });

  const payload = {
    course_id,
    ord: parseInt(f.get('ord') || '1', 10) || 1,
    title: (f.get('title') || '').toString().trim(),
    description: (f.get('description') || '').toString().trim() || null,
    meeting_at: f.get('meeting_at')?.toString() || null,
    meeting_url: (f.get('meeting_url') || '').toString().trim() || null,
    meeting_location: (f.get('meeting_location') || '').toString().trim() || null,
    slides_url: (f.get('slides_url') || '').toString().trim() || null,
    assignment_title: (f.get('assignment_title') || '').toString().trim() || null,
    assignment_body: (f.get('assignment_body') || '').toString().trim() || null,
    assignment_due_at: f.get('assignment_due_at')?.toString() || null,
    todo_items: (f.get('todo_items') || '').toString()
      .split('\n').map(s => s.trim()).filter(Boolean),
  };
  if (!payload.title) return NextResponse.json({ error: 'title required' }, { status: 400 });

  const admin = createAdminClient();
  if (id) await admin.from('course_lessons').update(payload).eq('id', id);
  else await admin.from('course_lessons').insert(payload);

  return NextResponse.redirect(new URL(`/admin/courses/${course_id}`, req.url), { status: 303 });
}
