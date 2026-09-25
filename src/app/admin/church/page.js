import Link from 'next/link';
import Avatar from '@/components/Avatar';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';

// The church profile is the author of every system-authored post — promotion
// announcements, and anything else that speaks for the church rather than a
// member. Super admins edit its name and avatar here. Everyone else sees a
// polite refusal.
export const dynamic = 'force-dynamic';

const CHURCH_ID = '11111111-1111-4111-8111-111111111111';

export default async function AdminChurchPage() {
  const { profile } = await getSessionAndProfile();
  if (profile?.role !== 'super_admin') {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Super admins only</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          The church account is edited by the super admin so the byline stays
          consistent across every announcement.
        </p>
        <Link href="/admin" className="btn-primary mt-8">Back to admin</Link>
      </section>
    );
  }

  const supabase = createClient();
  const { data: church } = await supabase
    .from('profiles')
    .select('id, full_name, avatar_url')
    .eq('id', CHURCH_ID)
    .maybeSingle();

  return (
    <div className="stack">
      <header>
        <h1 className="text-3xl">Church account</h1>
        <p className="mt-2 max-w-prose text-ink/65">
          This account writes the promotion announcements and any other post
          that speaks as the church. The name and photo here are what shows
          up in the feed and in the notification bell.
        </p>
      </header>

      {!church ? (
        <p className="card text-ink/70">
          The church account has not been provisioned yet. Run the
          20260916_church_account.sql migration first.
        </p>
      ) : (
        <form action="/api/admin/church-profile" method="post" className="card space-y-5">
          <div className="flex items-center gap-4">
            <Avatar url={church.avatar_url} name={church.full_name} size={64} fit="contain" />
            <div className="min-w-0">
              <p className="font-medium truncate">{church.full_name}</p>
              <p className="truncate text-xs text-ink/50">{church.avatar_url}</p>
            </div>
          </div>

          <div>
            <label className="label" htmlFor="full_name">Display name</label>
            <input
              id="full_name"
              name="full_name"
              type="text"
              defaultValue={church.full_name}
              className="input"
              required
            />
          </div>

          <div>
            <label className="label" htmlFor="avatar_url">Avatar URL</label>
            <input
              id="avatar_url"
              name="avatar_url"
              type="text"
              defaultValue={church.avatar_url || ''}
              placeholder="/logo.png or a full https:// URL"
              className="input"
            />
            <p className="mt-1 text-xs text-ink/45">
              Paste an uploaded image URL, or leave as <code>/logo.png</code> to use the site logo.
            </p>
          </div>

          <div className="flex justify-end">
            <button type="submit" className="btn-primary">Save</button>
          </div>
        </form>
      )}
    </div>
  );
}
