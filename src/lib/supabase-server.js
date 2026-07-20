import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { createClient as createSbClient } from '@supabase/supabase-js';

const NGROK_BYPASS = { 'ngrok-skip-browser-warning': 'true' };

export function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() { return cookieStore.getAll(); },
        setAll(list) {
          try { list.forEach(({ name, value, options }) => cookieStore.set(name, value, options)); }
          catch { /* Server Component; ignore */ }
        },
      },
      global: { headers: NGROK_BYPASS },
    }
  );
}

// Service-role client for privileged admin actions (password reset, delete user).
// Only import this from route handlers or server actions — never from client code.
export function createAdminClient() {
  return createSbClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: NGROK_BYPASS },
    }
  );
}

export async function getSessionAndProfile() {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { user: null, profile: null };
  const { data: profile } = await supabase
    .from('profiles').select('*').eq('id', user.id).single();
  return { user, profile };
}
