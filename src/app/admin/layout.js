import Link from 'next/link';
import AdminNav from '@/components/AdminNav';
import { getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff, isAdmin } from '@/lib/roles';

/**
 * One shell for every admin page.
 *
 * The access check lives here rather than being repeated at the top of each
 * page, so a new admin page cannot be added without it. Individual pages still
 * check anything narrower, such as an admin-only action inside a page
 * moderators may otherwise open.
 */
export default async function AdminLayout({ children }) {
  const { profile } = await getSessionAndProfile();

  if (!isStaff(profile?.role)) {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Not your area</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          This part of the site is for church leaders and staff.
        </p>
        <Link href="/" className="btn-primary mt-8">Back to home</Link>
      </section>
    );
  }

  return (
    <div className="stack">
      <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.3em]">
          Behind the scenes
        </p>
        <p className="text-xs text-ink/45">
          {profile.full_name} · {profile.role.replace('_', ' ')}
        </p>
      </div>

      <AdminNav isAdmin={isAdmin(profile.role)} />

      {children}
    </div>
  );
}
