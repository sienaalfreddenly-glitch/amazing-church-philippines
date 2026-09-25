import { NextResponse } from 'next/server';
import { revalidatePath } from 'next/cache';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { BLOCKS_BY_SLUG } from '@/lib/content-slugs';

// Super admin only. The RLS policy on site_content already enforces this at
// the database, but we also refuse at the edge so a wrong role sees an honest
// error rather than a silent no-op.
export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (profile?.role !== 'super_admin') {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const form = await req.formData();
  const slug = String(form.get('slug') || '');
  const body = String(form.get('body') ?? '');

  // The slug must be one we actually render. A typo would create an orphan
  // row that no page reads, which is confusing rather than harmful.
  if (!BLOCKS_BY_SLUG[slug]) {
    return NextResponse.json({ error: 'unknown slug' }, { status: 400 });
  }

  const trimmed = body.trim();
  const admin = createAdminClient();

  if (trimmed === '') {
    // Empty means "reset to default": drop the row so getContent falls back
    // to the code-side default rather than storing an empty string that
    // would blank the block on the site.
    await admin.from('site_content').delete().eq('slug', slug);
  } else {
    await admin.from('site_content').upsert({
      slug,
      body,
      updated_at: new Date().toISOString(),
      updated_by: profile.id,
    });
  }

  // Every page reads content on render, but the home page and the two policy
  // pages are cached; nudge them so the change is visible without waiting for
  // the next revalidation window.
  revalidatePath('/');
  revalidatePath('/terms');
  revalidatePath('/privacy');
  revalidatePath('/admin/content');

  return NextResponse.redirect(new URL('/admin/content', req.url), { status: 303 });
}
