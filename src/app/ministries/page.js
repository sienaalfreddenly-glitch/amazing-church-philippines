import Link from 'next/link';
import Avatar from '@/components/Avatar';
import Reveal from '@/components/Reveal';
import Spotlight from '@/components/Spotlight';
import MinistryInterestButton from '@/components/MinistryInterestButton';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';

export const metadata = {
  title: 'Ministries',
  description: 'Serve with the ushering, worship, or tech and media team at Amazing Church Philippines.',
};

// Ministry wording is edited in the database, so this page is never cached for
// long enough to show a stale description.
export const revalidate = 60;

export default async function MinistriesPage() {
  const { user, profile } = await getSessionAndProfile();
  const approved = profile?.account_status === 'approved';
  const supabase = createClient();

  const { data: ministries } = await supabase
    .from('ministries')
    .select('id, slug, name, summary, calling, scripture, scripture_ref, duties, leader_id')
    .eq('is_active', true)
    .order('sort');

  // RLS limits this to the reader's own rows, so it answers "which of these
  // have I already put my hand up for" and nothing else.
  const { data: mine } = user
    ? await supabase.from('ministry_interests').select('ministry_id')
    : { data: [] };
  const myInterests = new Set((mine || []).map((r) => r.ministry_id));

  // Who is actually serving. Confirmed members only, and unlike the interested
  // list this is not a secret: the congregation should know who is on the sound
  // desk. One call covers every ministry.
  const { data: teamRows } = user ? await supabase.rpc('ministry_teams') : { data: [] };
  const teamByMinistry = new Map();
  for (const row of teamRows || []) {
    const list = teamByMinistry.get(row.ministry_id) || [];
    list.push(row);
    teamByMinistry.set(row.ministry_id, list);
  }

  return (
    <div className="space-y-12">
      <Reveal>
        <header className="max-w-prose">
          <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.3em]">Serve</p>
          <h1 className="mt-3 text-4xl sm:text-5xl">Ministries</h1>
          <p className="mt-4 text-ink/65">
            Every one of these teams is short of people, and none of them need you to be
            impressive. If something here stirs you, put your hand up and a leader will talk
            it through with you.
          </p>
          <hr className="gilt-rule mt-6" />
        </header>
      </Reveal>

      {/* Deliberately a stacked list rather than three equal columns: each
          ministry gets room for its calling and its duties. */}
      <div className="space-y-8">
        {(ministries || []).map((m, i) => (
          <Reveal key={m.id} delay={i * 90}>
            <Spotlight className="rounded-2xl">
              <article className="card card-body sm:p-8">
                <div className="grid gap-8 md:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
                  <div>
                    <h2 className="text-2xl sm:text-3xl">{m.name}</h2>
                    <p className="mt-1 text-sm text-ink/55">{m.summary}</p>

                    <blockquote className="mt-5 border-l-2 border-gilt/60 pl-4">
                      <p className="font-display text-lg leading-snug text-ink/80">{m.scripture}</p>
                      <cite className="mt-1.5 block text-xs font-semibold not-italic tracking-wide text-brand">
                        {m.scripture_ref}
                      </cite>
                    </blockquote>

                    <p className="mt-5 max-w-prose text-ink/70">{m.calling}</p>
                  </div>

                  <div>
                    <h3 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink/50">
                      What it asks of you
                    </h3>
                    <ul className="mt-3 space-y-2">
                      {(m.duties || []).map((duty) => (
                        <li key={duty} className="flex gap-2.5 text-sm text-ink/70">
                          <span aria-hidden="true" className="mt-2 h-1 w-1 shrink-0 rounded-full bg-gilt" />
                          <span>{duty}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                {/* The people already doing this. Puts faces to the ask, and
                    tells a newcomer who to talk to. */}
                {(() => {
                  const team = teamByMinistry.get(m.id) || [];
                  if (!team.length) return null;
                  return (
                    <div className="mt-6 border-t border-silver-light pt-4">
                      <h3 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink/50">
                        Serving on this team
                      </h3>
                      <ul className="mt-3 flex flex-wrap gap-x-5 gap-y-3">
                        {team.map((person) => (
                          <li key={person.profile_id} className="flex items-center gap-2.5">
                            <Avatar url={person.avatar_url} name={person.full_name} size={32} />
                            <span className="text-sm">
                              <span className="font-medium">{person.full_name}</span>
                              {person.role_in_team && (
                                <span className="block text-xs text-ink/50">{person.role_in_team}</span>
                              )}
                            </span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  );
                })()}

                {approved ? (
                  <MinistryInterestButton
                    ministryId={m.id}
                    ministryName={m.name}
                    initiallyInterested={myInterests.has(m.id)}
                  />
                ) : (
                  <div className="card-foot">
                    <Link href={user ? '/pending' : '/signup'} className="btn-outline">
                      {user ? 'Waiting for approval' : 'Join the community to volunteer'}
                    </Link>
                  </div>
                )}

                {/* Leaders get a way through to the list of volunteers. */}
                {(isStaff(profile?.role) || m.leader_id === user?.id) && (
                  <p className="mt-3 text-sm">
                    <Link
                      href={`/ministries/${m.slug}/interested`}
                      className="text-brand underline-offset-4 hover:underline"
                    >
                      See who is interested
                    </Link>
                  </p>
                )}
              </article>
            </Spotlight>
          </Reveal>
        ))}
      </div>
    </div>
  );
}
