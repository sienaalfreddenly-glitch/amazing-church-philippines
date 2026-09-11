import { NextResponse } from 'next/server';
import { SERVER_SUPABASE_URL, TUNNEL_HEADERS } from '@/lib/supabase-config';

// Proxy for Supabase Storage public objects.
// Needed because browsers loading media directly from the ngrok-free.dev
// tunnel get served the ngrok interstitial HTML instead of the file.
// Requests here pass `ngrok-skip-browser-warning` so the tunnel returns
// the real binary.
export const runtime = 'nodejs';

export async function GET(req, { params }) {
  const path = (params.path || []).map(encodeURIComponent).join('/');
  // Straight to Supabase. Using the public URL here sent every image out
  // through the tunnel and back in, which failed whenever the tunnel was
  // down and returned a 500 for each one.
  const src = `${SERVER_SUPABASE_URL}/storage/v1/object/public/${path}`;
  const range = req.headers.get('range');

  const upstream = await fetch(src, {
    headers: {
      ...TUNNEL_HEADERS,
      ...(range ? { Range: range } : {}),
    },
    cache: 'no-store',
  });

  const out = new Headers();
  const passthrough = ['content-type', 'content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified'];
  for (const h of passthrough) {
    const v = upstream.headers.get(h);
    if (v) out.set(h, v);
  }
  out.set('Cache-Control', 'public, max-age=3600, s-maxage=86400');
  return new NextResponse(upstream.body, { status: upstream.status, headers: out });
}
