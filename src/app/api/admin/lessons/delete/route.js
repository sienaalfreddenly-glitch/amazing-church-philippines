import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const f = await req.formData();
  const id = f.get('id')?.toString();
  const course_id = f.get('course_id')?.toString();
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 });
  await createAdminClient().from('course_lessons').delete().eq('id', id);
  return NextResponse.redirect(new URL(`/admin/courses/${course_id}`, req.url), { status: 303 });
}
