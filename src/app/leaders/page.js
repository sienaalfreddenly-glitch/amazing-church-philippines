import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import Avatar from '@/components/Avatar';
import MembersOnlyGate from '@/components/MembersOnlyGate';
import { isApproved } from '@/lib/roles';

export const dynamic = 'force-dynamic';

// Org-chart language: leaders are those explicitly flagged by an admin.
// Everyone else is a disciple.

export default async function LeadersPage() {
  const { user, profile } = await getSessionAndProfile();
  if (!user || !isApproved(profile)) {
    return <MembersOnlyGate title="Leaders"
      description="Meet our shepherds and see the disciples they lead." />;
  }

  const supabase = createClient();
  const { data: people } = await supabase
    .from('profiles')
    .select('id, full_name, email, avatar_url, role, leader_id, is_leader, contact_number')
    .eq('account_status', 'approved')
    .neq('role', 'super_admin')      // Super Admin doesn't appear on the org chart
    .order('full_name', { ascending: true });

  const roster = people || [];
  const byLeader = new Map();
  for (const p of roster) {
    const k = p.leader_id || '__root__';
    if (!byLeader.has(k)) byLeader.set(k, []);
    byLeader.get(k).push(p);
  }
  const leadersList = roster.filter(p => p.is_leader);
  const unassigned = roster.filter(p => !p.leader_id && !p.is_leader);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl">Organizational Chart</h1>
        <p className="text-ink/60">Leaders and their Disciples.</p>
      </div>

      {leadersList.length === 0 && (
        <p className="card text-ink/60">
          No leaders designated yet. Admins can mark members as leaders from <a className="text-brand underline" href="/admin/users">Manage users</a> (flip <em>Is leader</em> to yes).
        </p>
      )}

      <div className="grid md:grid-cols-2 gap-6">
        {leadersList.map(leader => (
          <LeaderCard key={leader.id} leader={leader} team={byLeader.get(leader.id) || []} />
        ))}
      </div>

      {unassigned.length > 0 && (
        <section>
          <h2 className="text-xl mb-3">Disciples without a leader</h2>
          <div className="card">
            <ul className="divide-y divide-silver-light">
              {unassigned.map(p => (
                <li key={p.id} className="flex items-center gap-3 py-2">
                  <Avatar url={p.avatar_url} name={p.full_name} size={32} />
                  <div className="flex-1">
                    <p className="text-sm font-medium">{p.full_name}</p>
                    <p className="text-xs text-ink/60">{p.email}</p>
                  </div>
                  <span className="badge bg-silver-light text-ink/70">Disciple</span>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}
    </div>
  );
}

function LeaderCard({ leader, team }) {
  return (
    <div className="card">
      <div className="flex items-center gap-3 pb-3 border-b border-silver-light">
        <Avatar url={leader.avatar_url} name={leader.full_name} size={56} />
        <div>
          <p className="font-medium">{leader.full_name}</p>
          <p className="text-xs uppercase tracking-wide text-brand">Leader</p>
          {leader.contact_number && <p className="text-xs text-ink/60">{leader.contact_number}</p>}
        </div>
      </div>
      <div className="pt-3">
        <p className="text-xs uppercase tracking-wide text-ink/50 mb-2">
          Disciples ({team.length})
        </p>
        {team.length ? (
          <ul className="space-y-2">
            {team.map(m => (
              <li key={m.id} className="flex items-center gap-3">
                <Avatar url={m.avatar_url} name={m.full_name} size={32} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{m.full_name}</p>
                  <p className="text-xs text-ink/60 truncate">{m.contact_number || m.email}</p>
                </div>
                <span className="badge bg-silver-light text-ink/70 text-xs">
                  {m.is_leader ? 'Leader' : 'Disciple'}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-ink/50">No disciples assigned yet.</p>
        )}
      </div>
    </div>
  );
}
