'use client';
import { createBrowserClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, AUTH_STORAGE_KEY, TUNNEL_HEADERS } from './supabase-config';

export function createClient() {
  return createBrowserClient(
    PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      // Must match the server's key, or each side writes a cookie the other
      // cannot find and login silently does nothing.
      auth: { storageKey: AUTH_STORAGE_KEY },
      global: { headers: TUNNEL_HEADERS },
    }
  );
}
