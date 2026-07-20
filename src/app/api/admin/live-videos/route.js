import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isStaff(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  const form = await req.formData();
  const action = form.get('action');
  const admin = createAdminClient();

  if (action === 'delete') {
    const id = form.get('id');
    await admin.from('live_videos').delete().eq('id', id);
  } else {
    const title = (form.get('title') || '').toString().trim();
    const video_url = (form.get('video_url') || '').toString().trim();
    const occurred_on = (form.get('occurred_on') || '').toString().trim();
    const series_raw = (form.get('series_id') || '').toString();
    const series_id = series_raw || null;
    if (title && video_url && occurred_on) {
      await admin.from('live_videos').insert({ title, video_url, occurred_on, series_id, created_by: profile.id });
    }
  }
  return NextResponse.redirect(new URL('/live', req.url), { status: 303 });
}
