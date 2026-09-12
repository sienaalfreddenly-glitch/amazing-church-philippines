import { createServerClient } from '@supabase/ssr';
import { NextResponse } from 'next/server';
import { SERVER_SUPABASE_URL, AUTH_STORAGE_KEY, TUNNEL_HEADERS, timeoutFetch } from '@/lib/supabase-config';

export async function middleware(request) {
  let response = NextResponse.next({ request });
  const supabase = createServerClient(
    SERVER_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      auth: { storageKey: AUTH_STORAGE_KEY },
      cookies: {
        getAll() { return request.cookies.getAll(); },
        setAll(list) {
          list.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
      global: { headers: TUNNEL_HEADERS, fetch: timeoutFetch() },
    }
  );

  // Never let a slow or down Supabase take the site with it. This runs on every
  // request, so an unbounded call here is a site-wide outage; treating the
  // failure as "not signed in" degrades to the anonymous page instead.
  let user = null;
  try {
    ({ data: { user } } = await supabase.auth.getUser());
  } catch {
    user = null;
  }

  // Give anyone who is not signed in a visitor id, so they can be handed their
  // own daily verse. A server component cannot set a cookie, and the middleware
  // already owns the response, so this is the one place it can be minted. It is
  // HttpOnly and server-generated: a browser can neither read it nor choose it.
  if (!user && !request.cookies.get('acp_visitor')) {
    // crypto is a global in the Edge runtime the middleware runs on; node:crypto is not available there.
    response.cookies.set('acp_visitor', crypto.randomUUID(), {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
      maxAge: 60 * 60 * 24 * 180,
    });
  }

  // Force change-password redirect when the flag is set
  if (user) {
    const path = request.nextUrl.pathname;
    const isSafe =
      path.startsWith('/api') ||
      path.startsWith('/_next') ||
      path.startsWith('/uploads') ||
      path === '/account/change-password' ||
      path === '/auth/callback' ||
      path === '/login' ||
      path === '/logout';
    if (!isSafe) {
      try {
        const { data: profile } = await supabase
          .from('profiles').select('must_change_password').eq('id', user.id).maybeSingle();
        if (profile?.must_change_password) {
          return NextResponse.redirect(new URL('/account/change-password', request.url));
        }
      } catch {
        // Same reasoning as above: a stalled lookup must not block the request.
        // Missing the redirect on one page load is recoverable; a timeout is not.
      }
    }
  }

  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|logo.jpg|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
