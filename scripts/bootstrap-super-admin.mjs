import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';

// tiny .env.local reader
const env = Object.fromEntries(
  readFileSync(new URL('../.env.local', import.meta.url), 'utf8')
    .split(/\r?\n/).filter(Boolean).filter(l => !l.startsWith('#'))
    .map(l => { const i = l.indexOf('='); return [l.slice(0,i), l.slice(i+1)]; })
);

const email = process.argv[2];
const fullName = process.argv[3] || 'Super Admin';
if (!email) { console.error('usage: node scripts/bootstrap-super-admin.mjs <email> "[Full Name]"'); process.exit(1); }

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const tempPassword = 'Temp-' + Math.random().toString(36).slice(2, 10) + '!Aa1';

let userId;
const { data: created, error: createErr } =
  await admin.auth.admin.createUser({
    email, password: tempPassword, email_confirm: true,
    user_metadata: { full_name: fullName },
  });

if (createErr) {
  if (createErr.code !== 'email_exists' && !/already registered|already exists/i.test(createErr.message)) throw createErr;
  const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
  userId = list.users.find(u => u.email?.toLowerCase() === email.toLowerCase())?.id;
  if (!userId) throw new Error('User exists but could not be found');
  console.log('User already existed — reusing:', userId);
} else {
  userId = created.user.id;
  console.log('Created auth user:', userId);
}

// Ensure profile row exists (trigger may not fire on admin-create in some setups)
const { data: existingProfile } = await admin.from('profiles').select('id').eq('id', userId).maybeSingle();
if (!existingProfile) {
  await admin.from('profiles').insert({ id: userId, email, full_name: fullName });
  console.log('Inserted profile row');
}

const { error: upErr } = await admin.from('profiles')
  .update({ role: 'super_admin', account_status: 'approved', full_name: fullName })
  .eq('id', userId);
if (upErr) throw upErr;
console.log('Promoted to super_admin + approved');

// Send password-reset email so the user chooses their own password
const { error: resetErr } = await admin.auth.resetPasswordForEmail(email, {
  redirectTo: 'http://localhost:3000/login',
});
if (resetErr) console.warn('Reset email failed:', resetErr.message);
else console.log('Password-reset email sent to', email);

console.log('\nTemporary password (use if the reset email is delayed):', tempPassword);
