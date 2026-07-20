import { NextResponse } from 'next/server';
import { createAdminClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

function generateTempPassword() {
  const abc = 'ABCDEFGHJKMNPQRSTUVWXYZ';       // no I, L, O
  const num = '23456789';                       // no 0, 1
  const low = 'abcdefghijkmnpqrstuvwxyz';       // no l, o
  const pool = abc + num + low + '!@#$';
  const pick = () => pool[Math.floor(Math.random() * pool.length)];
  // Guarantee at least one from each class + total length 12
  return [
    abc[Math.floor(Math.random()*abc.length)],
    num[Math.floor(Math.random()*num.length)],
    low[Math.floor(Math.random()*low.length)],
    '!', pick(), pick(), pick(), pick(), pick(), pick(), pick(), pick(),
  ].sort(() => Math.random() - 0.5).join('');
}

export async function POST(req) {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) return NextResponse.json({ error: 'forbidden' }, { status: 403 });

  const { id, password } = await req.json().catch(() => ({}));
  if (!id) return NextResponse.json({ error: 'user id required' }, { status: 400 });

  const temp = (password && password.length >= 8) ? password : generateTempPassword();
  const admin = createAdminClient();

  const { error: authErr } = await admin.auth.admin.updateUserById(id, {
    password: temp,
    email_confirm: true,
  });
  if (authErr) return NextResponse.json({ error: authErr.message }, { status: 400 });

  await admin.from('profiles').update({ must_change_password: true }).eq('id', id);

  return NextResponse.json({ ok: true, password: temp });
}
