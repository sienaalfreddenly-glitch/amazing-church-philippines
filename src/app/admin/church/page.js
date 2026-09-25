import Link from 'next/link';
import Avatar from '@/components/Avatar';
import ChurchAvatarUploader from '@/components/ChurchAvatarUploader';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import AutoForm from '@/components/AutoForm';

export const dynamic = 'force-dynamic';

const CHURCH_ID = '11111111-1111-4111-8111-111111111111';

// One page for the super admin to run the church account:
//   1. Edit its display name and avatar (upload or paste URL).
//   2. Grant or revoke individual admins and moderators the right to post,
//      comment, and start discussions as the church without switching login.
export default async function AdminChurchPage() {
  const { profile } = await getSessionAndProfile();
  if (profile?.role !== 'super_admin') {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Super admins only</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          The church account is edited by the super admin so its byline and
          the list of people who can speak for it stay in one pair of hands.
        </p>
        <Link href="/admin" className="btn-primary mt-8">Back to admin</Link>
      </section>
    );
  }

  const supabase = createClient();
  const [{ data: church }, { data: staff }] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, full_name, avatar_url')
      .eq('id', CHURCH_ID)
      .maybeSingle(),
    supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, role, can_post_as_church')
      .in('role', ['admin', 'moderator'])
      .order('full_name', { ascending: true }),
  ]);

  return (
    <div className="stack">
      <header>
        <h1 className="text-3xl">Church account</h1>
        <p className="mt-2 max-w-prose text-ink/65">
          This account writes the promotion announcements and any other post
          that speaks as the church. Edit its name and avatar here, and pick
          who else may post, comment, or start a discussion as the church
          without logging in as it.
        </p>
      </header>

      {!church ? (
        <p className="card text-ink/70">
          The church account has not been provisioned yet. Run the
          20260916_church_account.sql migration first.
        </p>
      ) : (
        <>
          <section className="card space-y-5">
            <h2 className="text-xl">Profile</h2>
            <div className="flex items-center gap-4">
              <Avatar url={church.avatar_url} name={church.full_name} size={72} fit="contain" />
              <div className="min-w-0">
                <p className="font-medium truncate">{church.full_name}</p>
                <p className="truncate text-xs text-ink/50">{church.avatar_url || 'No avatar set'}</p>
              </div>
            </div>

            <ChurchAvatarUploader
              currentUrl={church.avatar_url || ''}
              currentName={church.full_name}
            />
          </section>

          <section className="card">
            <div className="mb-4 flex items-baseline justify-between gap-3">
              <h2 className="text-xl">Who else may post as the church</h2>
              <span className="text-xs text-ink/50">
                Super admins always may
              </span>
            </div>
            {(staff || []).length === 0 ? (
              <p className="text-sm text-ink/60">
                No admins or moderators yet. Promote someone to Admin or Moderator
                from <Link href="/admin/users" className="text-brand underline">Members</Link> first.
              </p>
            ) : (
              <ul className="divide-y divide-silver-light">
                {staff.map((u) => (
                  <li key={u.id} className="flex items-center gap-3 py-3">
                    <Avatar url={u.avatar_url} name={u.full_name} size={36} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{u.full_name}</p>
                      <p className="truncate text-xs text-ink/55">{u.email} · {u.role === 'admin' ? 'Admin' : 'Moderator'}</p>
                    </div>
                    <AutoForm action="/api/admin/church-access" className="shrink-0">
                      <input type="hidden" name="id" value={u.id} />
                      <select
                        name="can"
                        defaultValue={u.can_post_as_church ? 'true' : 'false'}
                        className="input"
                        aria-label={`Church posting for ${u.full_name}`}
                      >
                        <option value="false">Off</option>
                        <option value="true">On</option>
                      </select>
                    </AutoForm>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </div>
  );
}
