'use client';
import { createBrowserClient } from '@supabase/ssr';

// The `ngrok-skip-browser-warning` header prevents ngrok-free.dev from
// serving its HTML interstitial to browser fetches, which would otherwise
// break auth + realtime when Supabase is exposed through an ngrok tunnel.
const NGROK_BYPASS = { 'ngrok-skip-browser-warning': 'true' };

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    { global: { headers: NGROK_BYPASS } }
  );
}
