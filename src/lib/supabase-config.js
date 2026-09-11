/**
 * One place that decides which Supabase address to use.
 *
 * The browser and the server need different addresses for the same instance.
 * The browser can only reach Supabase through the public tunnel, while the
 * server is sitting next to it and should talk to it directly. Sending server
 * traffic out through the tunnel and back in is slow, and it fails outright
 * whenever the tunnel is down, which is what was breaking every image.
 */

/** What the browser calls. Public, goes through the tunnel. */
export const PUBLIC_SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/** What server code calls. Falls back to the public URL for local dev. */
export const SERVER_SUPABASE_URL =
  process.env.SUPABASE_INTERNAL_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * Auth cookie name, pinned explicitly.
 *
 * supabase-js derives its storage key from the first label of the URL host, so
 * a server on host.docker.internal would write `sb-host-auth-token` while the
 * browser wrote `sb-boastful-humbly-preheated-auth-token`. The two would never
 * see each other's session and login would appear to succeed and then do
 * nothing. Pinning the key on both clients makes the address irrelevant.
 *
 * Changing this value signs everyone out once.
 */
export const AUTH_STORAGE_KEY = 'sb-amazing-church-auth-token';

/**
 * ngrok serves an HTML interstitial to plain browser requests on its free
 * tier, which arrives instead of JSON or image bytes and breaks auth, realtime,
 * and media. This header opts out of it, and is harmless on any other host.
 */
export const TUNNEL_HEADERS = { 'ngrok-skip-browser-warning': 'true' };
