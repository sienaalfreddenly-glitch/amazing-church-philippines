import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import Avatar from '@/components/Avatar';
import SocialLinks from '@/components/SocialLinks';
import MembersOnlyGate from '@/components/MembersOnlyGate';
import { isApproved, householdLabel } from '@/lib/roles';

export const dynamic = 'force-dynamic';

/**
 * The household as a tree.
 *
 * Head Pastors sit at the top. Every other leader has a leader too, so a
 * Pastor is shown under the Head Pastor that shepherds them, and a Leader
 * under the Pastor that shepherds them. Disciples appear as the leaves of
 * whichever branch their shepherd sits on. Anyone flagged as a leader with
 * no shepherd is treated as a root; multiple roots are fine.
 */

const rankOf = (t) => {
  const s = (t || '').toLowerCase();
  if (s.startsWith('head pastor')) return 0;
  if (s.startsWith('pastor'))      return 1;
  if (s === 'leader')              return 2;
  return 3; // Disciple / untitled
};
const labelOf = householdLabel;

export default async function LeadersPage() {
  const { user, profile } = await getSessionAndProfile();
  if (!user || !isApproved(profile)) {
    return <MembersOnlyGate title="Leaders"
      description="Meet our shepherds and the household under their care." />;
  }

  const supabase = createClient();
  const { data: people } = await supabase
    .from('profiles')
    .select('id, full_name, email, avatar_url, role, leader_id, is_leader, title, facebook_url, instagram_url')
    .eq('account_status', 'approved')
    .neq('role', 'super_admin')      // Super Admin doesn't appear on the household
    .neq('id', '11111111-1111-4111-8111-111111111111') // Nor does the church profile
    .order('full_name', { ascending: true });

  // One call returns every number this viewer may see: their own, their group's,
  // or all of them for staff. Merged in below so SocialLinks can render it.
  const { data: contacts } = await supabase.rpc('visible_contacts');
  const contactById = new Map((contacts || []).map(c => [c.id, c.contact_number]));
  for (const p of people || []) p.contact_number = contactById.get(p.id) || null;

  const roster = people || [];
  const byLeader = new Map();
  for (const p of roster) {
    const k = p.leader_id || '__root__';
    if (!byLeader.has(k)) byLeader.set(k, []);
    byLeader.get(k).push(p);
  }
  // Sort every sibling bucket by rank then name so the tree reads the same at
  // every depth.
  for (const [, list] of byLeader) {
    list.sort((a, b) => rankOf(a.title) - rankOf(b.title) || a.full_name.localeCompare(b.full_name));
  }

  // Roots: leaders without a shepherd. Anyone flagged as a leader with a
  // dangling leader_id (their shepherd is not in the roster) also floats up
  // here, so nobody gets orphaned off the chart.
  const rosterIds = new Set(roster.map(p => p.id));
  const roots = roster
    .filter(p => p.is_leader && (!p.leader_id || !rosterIds.has(p.leader_id)))
    .sort((a, b) => rankOf(a.title) - rankOf(b.title) || a.full_name.localeCompare(b.full_name));

  // Disciples with no shepherd are called out separately, same as before.
  const stray = roster.filter(p => !p.leader_id && !p.is_leader);

  return (
    <div className="space-y-8">
      <div>
        <p className="gilt-text text-[11px] font-semibold uppercase tracking-[0.3em]">The household</p>
        <h1 className="mt-3 text-4xl sm:text-5xl">Shepherds and disciples</h1>
        <p className="mt-4 max-w-prose text-ink/65">
          Everyone here is under the care of someone, and the shepherds are
          under the care of someone too. If you have not been paired with a
          shepherd yet, any of them will point you to the right person.
        </p>
      </div>

      {roots.length === 0 && (
        <p className="card text-ink/60">
          No shepherds designated yet. Admins can set someone as Head Pastor,
          Pastor or Leader from <a className="text-brand underline" href="/admin/users">Manage users</a>.
        </p>
      )}

      <div className="space-y-8">
        {roots.map(root => (
          <PersonNode key={root.id} person={root} byLeader={byLeader} depth={0} />
        ))}
      </div>

      {stray.length > 0 && (
        <section>
          <h2 className="text-xl mb-3">Disciples without a shepherd</h2>
          <div className="card">
            <ul className="divide-y divide-silver-light">
              {stray.map(p => (
                <li key={p.id} className="flex items-center gap-3 py-2">
                  <Avatar url={p.avatar_url} name={p.full_name} size={32} />
                  <div className="flex-1">
                    <p className="text-sm font-medium">{p.full_name}</p>
                    <p className="text-xs text-ink/60">{p.email}</p>
                  </div>
                  <span className="badge bg-silver-light text-ink/70">{labelOf(p)}</span>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}
    </div>
  );
}

/**
 * A single tile in the tree.
 *
 * A leader gets a full card with their flock listed underneath; a disciple
 * gets a compact row. Every leader recursively renders their own leader
 * children indented, so the depth mirrors the chain from Head Pastor down.
 */
function PersonNode({ person, byLeader, depth }) {
  const children = byLeader.get(person.id) || [];
  const flock = children.filter(c => !c.is_leader);
  const subLeaders = children.filter(c => c.is_leader);

  if (!person.is_leader) {
    return <DiscipleRow person={person} />;
  }

  // Indent every level slightly so a Pastor's card sits inside their Head
  // Pastor's, and a Leader's card sits inside their Pastor's. Cap the indent
  // so a deep chain does not disappear off the right of the page.
  const indent = Math.min(depth, 3) * 20;

  return (
    <div className="space-y-4" style={{ marginLeft: indent }}>
      <div className="card">
        <div className="flex items-center gap-3 pb-3 border-b border-silver-light">
          <Avatar url={person.avatar_url} name={person.full_name} size={56} />
          <div className="min-w-0">
            <p className="font-medium truncate">{person.full_name}</p>
            <p className="text-xs uppercase tracking-wide text-brand">{labelOf(person)}</p>
            <SocialLinks profile={person} className="mt-1.5" />
          </div>
        </div>

        {flock.length > 0 && (
          <div className="pt-3">
            <p className="text-xs uppercase tracking-wide text-ink/50 mb-2">
              Flock ({flock.length})
            </p>
            <ul className="space-y-2">
              {flock.map(m => (
                <li key={m.id} className="flex items-center gap-3">
                  <Avatar url={m.avatar_url} name={m.full_name} size={32} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{m.full_name}</p>
                    <p className="text-xs text-ink/60 truncate">{m.contact_number || m.email}</p>
                  </div>
                  <span className="badge bg-silver-light text-ink/70 text-xs">
                    {labelOf(m)}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        )}

        {flock.length === 0 && subLeaders.length === 0 && (
          <p className="pt-3 text-sm text-ink/50">Nobody in their care yet.</p>
        )}
      </div>

      {subLeaders.map(child => (
        <PersonNode key={child.id} person={child} byLeader={byLeader} depth={depth + 1} />
      ))}
    </div>
  );
}

function DiscipleRow({ person }) {
  return (
    <div className="card flex items-center gap-3 py-2">
      <Avatar url={person.avatar_url} name={person.full_name} size={32} />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{person.full_name}</p>
        <p className="text-xs text-ink/60 truncate">{person.contact_number || person.email}</p>
      </div>
      <span className="badge bg-silver-light text-ink/70 text-xs">{labelOf(person)}</span>
    </div>
  );
}
