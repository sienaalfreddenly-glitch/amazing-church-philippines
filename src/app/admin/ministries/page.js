import Link from 'next/link';
import Avatar from '@/components/Avatar';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';

export const metadata = { title: 'Ministries · Admin' };

export default async function AdminMinistriesPage() {
  const { profile } = await getSessionAndProfile();
  if (!isAdmin(profile?.role)) {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Admins only</h1>
        <p className="mt-4 text-ink/65">Assigning ministry leaders is an admin task.</p>
        <Link href="/ministries" className="btn-primary mt-8">Back to ministries</Link>
      </section>
    );
  }

  const supabase = createClient();

  const [{ data: ministries }, { data: leaders }, { data: rows }] = await Promise.all([
    supabase.from('ministries').select('id, slug, name, summary, leader_id').order('sort'),
    supabase
      .from('profiles')
      .select('id, full_name, title')
      .eq('is_leader', true)
      .eq('account_status', 'approved')
      .order('full_name'),
    supabase.from('ministry_interests').select('ministry_id, status'),
  ]);

  // Counts per ministry, so an admin can see at a glance where people are
  // waiting for an answer.
  const tally = new Map();
  for (const r of rows || []) {
    const t = tally.get(r.ministry_id) || { interested: 0, member: 0, declined: 0 };
    t[r.status] = (t[r.status] || 0) + 1;
    tally.set(r.ministry_id, t);
  }

  const leaderById = new Map((leaders || []).map((l) => [l.id, l]));

  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-3xl sm:text-4xl">Ministries</h1>
        <p className="mt-2 max-w-prose text-ink/65">
          Put a leader in charge of each team. They will be the one notified when somebody
          volunteers, and the only person besides staff who can see that list.
        </p>
        <hr className="gilt-rule mt-5" />
      </header>

      <div className="space-y-4">
        {(ministries || []).map((m) => {
          const counts = tally.get(m.id) || { interested: 0, member: 0, declined: 0 };
          const current = leaderById.get(m.leader_id);

          return (
            <div key={m.id} className="card">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="min-w-0">
                  <h2 className="text-xl">{m.name}</h2>
                  <p className="mt-0.5 text-sm text-ink/55">{m.summary}</p>

                  <p className="nums mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    <span className="text-brand font-medium">{counts.member} serving</span>
                    <span className={counts.interested ? 'font-medium text-ink' : 'text-ink/45'}>
                      {counts.interested} waiting for an answer
                    </span>
                    {counts.declined > 0 && (
                      <span className="text-ink/45">{counts.declined} declined</span>
                    )}
                  </p>
                </div>

                <Link
                  href={`/ministries/${m.slug}/interested`}
                  className="btn-outline shrink-0"
                >
                  Open the list
                </Link>
              </div>

              <form
                action="/api/admin/ministries/set-leader"
                method="post"
                className="mt-5 flex flex-wrap items-end gap-3 border-t border-silver-light pt-4"
              >
                <input type="hidden" name="ministry_id" value={m.id} />

                <div className="min-w-[14rem] flex-1">
                  <label className="label" htmlFor={`leader-${m.id}`}>Leader in charge</label>
                  <select
                    id={`leader-${m.id}`}
                    name="leader_id"
                    defaultValue={m.leader_id || ''}
                    className="input"
                  >
                    <option value="">Nobody yet — every leader is notified</option>
                    {(leaders || []).map((l) => (
                      <option key={l.id} value={l.id}>
                        {l.full_name}{l.title ? ` · ${l.title}` : ''}
                      </option>
                    ))}
                  </select>
                </div>

                <button className="btn-primary">Save</button>

                {current && (
                  <p className="flex items-center gap-2 text-sm text-ink/55">
                    <Avatar name={current.full_name} size={24} />
                    Currently {current.full_name}
                  </p>
                )}
              </form>
            </div>
          );
        })}
      </div>
    </div>
  );
}
