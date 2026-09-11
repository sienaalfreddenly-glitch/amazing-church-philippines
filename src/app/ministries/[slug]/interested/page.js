import Link from 'next/link';
import { notFound } from 'next/navigation';
import Avatar from '@/components/Avatar';
import Reveal from '@/components/Reveal';
import SocialLinks from '@/components/SocialLinks';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';
import { eventDate } from '@/lib/format';

/**
 * Who has volunteered for one ministry.
 *
 * Row-level security already limits this table to the ministry's own leader and
 * to staff, so a member reaching this URL sees an empty list rather than other
 * people's names. The explicit check below is so they get an honest message
 * instead of a page that looks broken.
 */

export async function generateMetadata({ params }) {
  return { title: `Interested · ${params.slug.replace(/-/g, ' ')}` };
}

export default async function InterestedPage({ params }) {
  const { user, profile } = await getSessionAndProfile();
  const supabase = createClient();

  const { data: ministry } = await supabase
    .from('ministries')
    .select('id, slug, name, summary, leader_id')
    .eq('slug', params.slug)
    .single();

  if (!ministry) notFound();

  const allowed = isStaff(profile?.role) || (user && ministry.leader_id === user.id);

  if (!allowed) {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">{ministry.name}</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          This list is for the leaders of this ministry. If you volunteered, one of them
          will speak with you.
        </p>
        <Link href="/ministries" className="btn-primary mt-8">Back to ministries</Link>
      </section>
    );
  }

  const { data: interests } = await supabase
    .from('ministry_interests')
    .select('id, created_at, note, status, role_in_team, profile:profiles(id, full_name, avatar_url, email, title, facebook_url, instagram_url)')
    .eq('ministry_id', ministry.id)
    .order('created_at', { ascending: false });

  // Phone numbers are not readable through the profiles table, so they come
  // from the function that decides who may see which.
  const { data: contacts } = await supabase.rpc('visible_contacts');
  const contactById = new Map((contacts || []).map((c) => [c.id, c.contact_number]));

  const all = interests || [];
  // Split rather than filter in the markup: the two lists answer different
  // questions and deserve different emphasis.
  const waiting = all.filter((r) => r.status === 'interested');
  const team = all.filter((r) => r.status === 'member');
  const declined = all.filter((r) => r.status === 'declined');

  return (
    <div className="space-y-8">
      <Reveal>
        <header>
          <Link href="/ministries" className="btn-quiet -ml-2 mb-6">Back to ministries</Link>
          <h1 className="text-4xl sm:text-5xl">{ministry.name}</h1>
          <p className="mt-2 text-ink/60">{ministry.summary}</p>
          <p className="nums mt-4 flex flex-wrap gap-x-5 gap-y-1 text-sm">
            <span className="font-medium text-brand">{team.length} serving</span>
            <span className={waiting.length ? 'font-medium text-ink' : 'text-ink/45'}>
              {waiting.length} waiting for an answer
            </span>
          </p>
          <hr className="gilt-rule mt-5" />
        </header>
      </Reveal>

      {waiting.length > 0 && (
        <section aria-labelledby="waiting-heading">
          <h2 id="waiting-heading" className="text-xl">Waiting for an answer</h2>
          <ul className="mt-4 space-y-3">
            {waiting.map((row, i) => (
              <Reveal key={row.id} delay={i * 60} as="li">
                <Person row={row} contact={contactById.get(row.profile?.id)} slug={ministry.slug} />
              </Reveal>
            ))}
          </ul>
        </section>
      )}

      <section aria-labelledby="team-heading">
        <h2 id="team-heading" className="text-xl">On the team</h2>
        {team.length ? (
          <ul className="mt-4 space-y-3">
            {team.map((row, i) => (
              <Reveal key={row.id} delay={i * 60} as="li">
                <Person row={row} contact={contactById.get(row.profile?.id)} slug={ministry.slug} />
              </Reveal>
            ))}
          </ul>
        ) : (
          <div className="card card-static mt-4 py-10 text-center text-ink/60">
            <p className="font-medium text-ink/75">Nobody is serving on this team yet</p>
            <p className="mx-auto mt-1 max-w-sm text-sm">
              {waiting.length
                ? 'Someone above is waiting to hear from you.'
                : 'Mention it from the front, or speak to someone you have already noticed doing this without being asked.'}
            </p>
          </div>
        )}
      </section>

      {declined.length > 0 && (
        <details className="card card-static">
          <summary className="cursor-pointer text-sm font-medium text-ink/70">
            Not this season ({declined.length})
          </summary>
          <ul className="mt-4 space-y-3">
            {declined.map((row) => (
              <li key={row.id}>
                <Person row={row} contact={contactById.get(row.profile?.id)} slug={ministry.slug} />
              </li>
            ))}
          </ul>
        </details>
      )}

    </div>
  );
}

/**
 * One volunteer, with the controls to accept or stand them down.
 *
 * Plain forms posting to a route handler rather than a client component: this
 * is a rare, deliberate action by a leader, and a form works without JavaScript.
 */
function Person({ row, contact, slug }) {
  const onTeam = row.status === 'member';

  return (
    <div className="card">
      <div className="flex flex-wrap items-center gap-4">
        <Avatar url={row.profile?.avatar_url} name={row.profile?.full_name} size={44} />

        <div className="min-w-0 flex-1">
          <p className="font-medium">
            {row.profile?.full_name}
            {row.role_in_team && (
              <span className="ml-2 text-sm font-normal text-ink/55">{row.role_in_team}</span>
            )}
          </p>
          <SocialLinks profile={{ ...row.profile, contact_number: contact }} className="mt-1.5" />
          {row.note && <p className="mt-2 text-sm text-ink/65">{row.note}</p>}
        </div>

        <p className="nums shrink-0 text-xs text-ink/45">{eventDate(row.created_at)}</p>
      </div>

      <form
        action="/api/admin/ministries/set-status"
        method="post"
        className="mt-4 flex flex-wrap items-end gap-2.5 border-t border-silver-light pt-4"
      >
        <input type="hidden" name="interest_id" value={row.id} />
        <input type="hidden" name="slug" value={slug} />

        <div className="min-w-[10rem] flex-1">
          <label className="label" htmlFor={`role-${row.id}`}>Role on the team</label>
          <input
            id={`role-${row.id}`}
            name="role_in_team"
            className="input"
            placeholder="Sound, front door, vocals…"
            defaultValue={row.role_in_team || ''}
          />
        </div>

        {onTeam ? (
          <>
            <button name="status" value="member" className="btn-outline">Save role</button>
            <button name="status" value="declined" className="btn-quiet">Stand down</button>
          </>
        ) : (
          <>
            <button name="status" value="member" className="btn-primary">Add to the team</button>
            <button name="status" value="declined" className="btn-quiet">Not this season</button>
          </>
        )}
      </form>
    </div>
  );
}
