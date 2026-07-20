import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isStaff(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const f = await req.formData();
  const action = f.get('action');
  const admin = createAdminClient();

  if (action === 'delete') {
    // videos in the series just get series_id nulled via FK on delete set null
    await admin.from('live_series').delete().eq('id', f.get('id'));
  } else {
    const title = (f.get('title') || '').toString().trim();
    const description = (f.get('description') || '').toString().trim() || null;
    const cover_url = (f.get('cover_url') || '').toString().trim() || null;
    if (title) {
      await admin.from('live_series').upsert(
        { title, description, cover_url },
        { onConflict: 'title' });
    }
  }
  return NextResponse.redirect(new URL('/live', req.url), { status: 303 });
}
