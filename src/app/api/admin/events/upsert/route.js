import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

// datetime-local sends a naive 'YYYY-MM-DDTHH:MM' with no timezone. The
// church runs on Philippine time, so we interpret every submitted value as
// Asia/Manila (+08:00) before Postgres stores it as timestamptz. That keeps
// what the admin typed and what members see aligned regardless of the
// browser's own timezone or the server's.
function manilaToIso(v) {
  if (!v) return null;
  const s = String(v);
  // Already has a timezone (e.g. a browser using datetime-local with seconds
  // and an offset — vanishingly rare, but be tolerant).
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) return s;
  const withSeconds = s.length === 16 ? `${s}:00` : s;
  return `${withSeconds}+08:00`;
}

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isStaff(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const f = await req.formData();
  const id = f.get('id')?.toString() || null;
  const title = (f.get('title') || '').toString().trim();
  const description = (f.get('description') || '').toString().trim() || null;
  const starts_at = manilaToIso(f.get('starts_at')?.toString() || null);
  const ends_at   = manilaToIso(f.get('ends_at')?.toString()   || null);
  const location = (f.get('location') || '').toString().trim() || null;
  const cover_url = (f.get('cover_url') || '').toString().trim() || null;

  if (!title || !starts_at) return NextResponse.json({ error: 'title and start time required' }, { status: 400 });

  const admin = createAdminClient();
  const payload = { title, description, starts_at, ends_at, location, cover_url };
  if (id) await admin.from('events').update(payload).eq('id', id);
  else await admin.from('events').insert({ ...payload, created_by: profile.id });

  return NextResponse.redirect(new URL('/admin/events', req.url), { status: 303 });
}
