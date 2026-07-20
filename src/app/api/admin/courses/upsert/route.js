import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const form = await req.formData();
  const code = (form.get('code') || '').toString().trim();
  const name = (form.get('name') || '').toString().trim();
  const prereq_raw = (form.get('prereq_id') || '').toString();
  const prereq_id = prereq_raw || null;
  const description = (form.get('description') || '').toString().trim() || null;
  if (!code || !name) return NextResponse.json({ error: 'code and name required' }, { status: 400 });

  const admin = createAdminClient();
  await admin.from('courses').upsert({ code, name, prereq_id, description }, { onConflict: 'code' });
  return NextResponse.redirect(new URL('/admin/courses', req.url), { status: 303 });
}
