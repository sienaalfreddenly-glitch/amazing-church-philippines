import { NextResponse } from 'next/server';

// Proxy for Supabase Storage public objects.
// Needed because browsers loading media directly from the ngrok-free.dev
// tunnel get served the ngrok interstitial HTML instead of the file.
// Requests here pass `ngrok-skip-browser-warning` so the tunnel returns
// the real binary.
export const runtime = 'nodejs';

export async function GET(req, { params }) {
  const path = (params.path || []).map(encodeURIComponent).join('/');
  const src = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/${path}`;
  const range = req.headers.get('range');

  const upstream = await fetch(src, {
    headers: {
      'ngrok-skip-browser-warning': 'any',
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
