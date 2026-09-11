import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { createClient as createSbClient } from '@supabase/supabase-js';
import { SERVER_SUPABASE_URL, AUTH_STORAGE_KEY, TUNNEL_HEADERS } from './supabase-config';

export function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    // Server-side traffic goes straight to Supabase rather than out through
    // the public tunnel and back in.
    SERVER_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      // Pinned so the server reads the same cookie the browser wrote, even
      // though the two use different addresses.
      auth: { storageKey: AUTH_STORAGE_KEY },
      cookies: {
        getAll() { return cookieStore.getAll(); },
        setAll(list) {
          try { list.forEach(({ name, value, options }) => cookieStore.set(name, value, options)); }
          catch { /* Server Component; ignore */ }
        },
      },
      global: { headers: TUNNEL_HEADERS },
    }
  );
}

// Service-role client for privileged admin actions (password reset, delete user).
// Only import this from route handlers or server actions — never from client code.
export function createAdminClient() {
  return createSbClient(
    SERVER_SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: TUNNEL_HEADERS },
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
