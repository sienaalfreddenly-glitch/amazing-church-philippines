import Link from 'next/link';
import Avatar from '@/components/Avatar';
import Reveal from '@/components/Reveal';
import { createClient } from '@/lib/supabase-server';
import { getSessionAndProfile } from '@/lib/supabase-server';

export const metadata = {
  title: 'Organisation chart',
  description: 'Who leads what at Amazing Church Philippines, and who they care for.',
};

/**
 * The church organisation chart.
 *
 * Built from leader_id, which already describes who cares for whom, so the
 * chart is a view of real data rather than a second structure to maintain. The
 * root is whoever has no leader, which is the Head Pastor.
 */

// Walk the roster into a tree. Anyone whose leader is missing or not approved
// is attached to the root rather than dropped, so no member disappears from
// the chart because of a stale reference.
function buildTree(people) {
  const byId = new Map(people.map((p) => [p.id, { ...p, reports: [] }]));
  const roots = [];

  for (const node of byId.values()) {
    const parent = node.leader_id ? byId.get(node.leader_id) : null;
    if (parent && parent.id !== node.id) parent.reports.push(node);
    else roots.push(node);
  }

  // Leaders first, then alphabetical, at every level.
  const sort = (list) => {
    list.sort((a, b) =>
      a.reports.length === b.reports.length
        ? a.full_name.localeCompare(b.full_name)
        : b.reports.length - a.reports.length,
    );
    list.forEach((n) => sort(n.reports));
  };
  sort(roots);

  return roots;
}

function Node({ person, depth = 0 }) {
  const hasReports = person.reports.length > 0;

  return (
    <li className="org-node">
      <div className={`org-card ${depth === 0 ? 'org-card-root' : ''}`}>
        <Avatar url={person.avatar_url} name={person.full_name} size={depth === 0 ? 56 : 40} />
        <div className="min-w-0">
          <p className="truncate font-medium text-ink">{person.full_name}</p>
          {person.title && (
            <p className={`truncate text-xs ${depth === 0 ? 'gilt-text font-semibold' : 'text-ink/55'}`}>
              {person.title}
            </p>
          )}
          {hasReports && (
            <p className="nums mt-0.5 text-xs text-ink/40">
              {person.reports.length} {person.reports.length === 1 ? 'member' : 'members'}
            </p>
          )}
        </div>
      </div>

      {hasReports && (
        <ul className="org-children">
          {person.reports.map((child) => (
            <Node key={child.id} person={child} depth={depth + 1} />
          ))}
        </ul>
      )}
    </li>
  );
}

export default async function OrgChartPage() {
  const { profile } = await getSessionAndProfile();

  if (!profile || profile.account_status !== 'approved') {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Organisation chart</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          The chart is for approved members. Sign in to see who leads what.
        </p>
        <Link href="/login" className="btn-primary mt-8">Sign in</Link>
      </section>
    );
  }

  const supabase = createClient();
  const { data: people } = await supabase.rpc('org_chart');
  const tree = buildTree(people || []);

  return (
    <div className="space-y-10">
      <Reveal>
        <header>
          <h1 className="text-4xl sm:text-5xl">Organisation chart</h1>
          <p className="mt-3 max-w-prose text-ink/65">
            Who leads what, and who they care for. Built from the leader each member is
            assigned, so it stays true as people are assigned and reassigned.
          </p>
          <hr className="gilt-rule mt-6" />
        </header>
      </Reveal>

      {tree.length ? (
        <Reveal delay={100}>
          <ul className="org-tree">
            {tree.map((root) => (
              <Node key={root.id} person={root} />
            ))}
          </ul>
        </Reveal>
      ) : (
        <div className="card card-static py-12 text-center text-ink/60">
          <p className="font-medium text-ink/75">Nobody to show yet</p>
          <p className="mx-auto mt-1 max-w-xs text-sm">
            The chart fills in as members are approved and assigned to a leader.
          </p>
        </div>
      )}
    </div>
  );
}
