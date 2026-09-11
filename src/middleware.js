import { createServerClient } from '@supabase/ssr';
import { NextResponse } from 'next/server';
import { SERVER_SUPABASE_URL, AUTH_STORAGE_KEY, TUNNEL_HEADERS } from '@/lib/supabase-config';

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
      global: { headers: TUNNEL_HEADERS },
    }
  );
  const { data: { user } } = await supabase.auth.getUser();

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
      const { data: profile } = await supabase
        .from('profiles').select('must_change_password').eq('id', user.id).maybeSingle();
      if (profile?.must_change_password) {
        return NextResponse.redirect(new URL('/account/change-password', request.url));
      }
    }
  }

  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|logo.jpg|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
