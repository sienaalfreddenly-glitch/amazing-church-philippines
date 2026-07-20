import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import Avatar from '@/components/Avatar';
import AutoForm from '@/components/AutoForm';
import ConfirmDeleteUserButton from '@/components/ConfirmDeleteUserButton';
import SetTempPasswordButton from '@/components/SetTempPasswordButton';

export const dynamic = 'force-dynamic';

export default async function ManageUsers() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');
  const supabase = createClient();
  const [{ data: users, error }, { data: allCompletions }] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, role, account_status, contact_number, leader_id, is_leader, created_at')
      .order('created_at', { ascending: false }),
    // Latest lesson completion per user — one row per completion, we pick the newest per user
    supabase.from('lesson_completions')
      .select('verified_at, enrollment:enrollments(user_id), lesson:course_lessons(title, ord, course:courses(code))')
      .order('verified_at', { ascending: false }),
  ]);

  const list = users || [];
  const leaders = list.filter(u => u.is_leader);
  const latestByUser = new Map();
  (allCompletions || []).forEach(c => {
    const uid = c.enrollment?.user_id;
    if (!uid || latestByUser.has(uid)) return; // completions already sorted desc
    latestByUser.set(uid, c);
  });

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-3xl">Users</h1>
          <p className="text-sm text-ink/60">Manage roles, approvals, and leader assignments.</p>
        </div>
        <span className="badge bg-silver-light">{list.length} total</span>
      </div>

      {error && <p className="text-sm text-red-700">Could not load users: {error.message}</p>}

      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-[11px] uppercase tracking-wider text-ink/50 border-b border-silver-light">
                <th className="px-5 py-3 font-semibold">Member</th>
                <th className="px-4 py-3 font-semibold">Contact</th>
                <th className="px-4 py-3 font-semibold">Role</th>
                <th className="px-4 py-3 font-semibold">Status</th>
                <th className="px-4 py-3 font-semibold">Is leader</th>
                <th className="px-4 py-3 font-semibold">Reports to</th>
                <th className="px-4 py-3 font-semibold">Last lesson</th>
                <th className="px-5 py-3 font-semibold text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {list.length === 0 && !error && (
                <tr><td colSpan="8" className="px-5 py-10 text-center text-ink/60">No users yet.</td></tr>
              )}
              {list.map(u => {
                const isSelf = u.id === profile.id;
                const isSuper = u.role === 'super_admin';
                const roleLocked = isSuper && profile.role !== 'super_admin';
                return (
                  <tr key={u.id} className="border-t border-silver-light hover:bg-silver-light/25 transition-colors">
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-3">
                        <Avatar url={u.avatar_url} name={u.full_name} size={38} />
                        <div className="min-w-0">
                          <p className="font-medium truncate">
                            {u.full_name}
                            {isSelf && <span className="ml-2 text-[10px] uppercase tracking-wider text-brand">you</span>}
                          </p>
                          <p className="text-xs text-ink/60 truncate">{u.email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-ink/70 whitespace-nowrap">
                      {u.contact_number || <span className="text-ink/30">—</span>}
                    </td>
                    <td className="px-4 py-3">
                      <AutoForm action="/api/admin/set-role">
                        <input type="hidden" name="id" value={u.id} />
                        <select name="role" defaultValue={u.role}
                          disabled={roleLocked}
                          className="input py-1.5 text-xs w-auto min-w-[7rem]">
                          <option value="user">user</option>
                          <option value="moderator">moderator</option>
                          <option value="admin">admin</option>
                          {profile.role === 'super_admin' && <option value="super_admin">super_admin</option>}
                        </select>
                      </AutoForm>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <span className={`badge ${
                          u.account_status === 'approved' ? 'bg-brand-50 text-brand-700'
                          : u.account_status === 'pending' ? 'bg-amber-50 text-amber-700'
                          : 'bg-red-50 text-red-700'}`}>{u.account_status}</span>
                        {u.account_status !== 'approved' && (
                          <form action="/api/admin/approve-user" method="post">
                            <input type="hidden" name="id" value={u.id} />
                            <input type="hidden" name="action" value="approve" />
                            <button className="text-xs text-brand hover:underline">Approve</button>
                          </form>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <AutoForm action="/api/admin/set-leader-flag">
                        <input type="hidden" name="id" value={u.id} />
                        <select name="is_leader" defaultValue={u.is_leader ? 'true' : 'false'}
                          className="input py-1.5 text-xs w-auto">
                          <option value="false">no</option>
                          <option value="true">yes</option>
                        </select>
                      </AutoForm>
                    </td>
                    <td className="px-4 py-3">
                      <AutoForm action="/api/admin/set-leader">
                        <input type="hidden" name="id" value={u.id} />
                        <select name="leader_id" defaultValue={u.leader_id || ''}
                          disabled={leaders.length === 0}
                          className="input py-1.5 text-xs w-auto min-w-[10rem] max-w-[14rem]">
                          <option value="">— none —</option>
                          {leaders.filter(l => l.id !== u.id).map(l => (
                            <option key={l.id} value={l.id}>{l.full_name}</option>
                          ))}
                        </select>
                      </AutoForm>
                    </td>
                    <td className="px-4 py-3 text-xs">
                      {(() => {
                        const c = latestByUser.get(u.id);
                        if (!c) return <span className="text-ink/40">—</span>;
                        return (
                          <div className="min-w-0">
                            <div className="truncate">
                              <span className="text-brand font-semibold">{c.lesson?.course?.code}</span>{' '}
                              L{c.lesson?.ord} · <span className="text-ink/80">{c.lesson?.title}</span>
                            </div>
                            <div className="text-ink/50">{new Date(c.verified_at).toLocaleDateString()}</div>
                          </div>
                        );
                      })()}
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex items-center justify-end gap-1.5">
                        <form action="/api/admin/reset-password" method="post">
                          <input type="hidden" name="id" value={u.id} />
                          <button title="Send password reset email"
                            className="text-xs px-2.5 py-1 rounded-full border border-silver-light hover:border-brand hover:text-brand transition-colors">
                            Email reset
                          </button>
                        </form>
                        <SetTempPasswordButton id={u.id} name={u.full_name} />
                        {!isSelf && !roleLocked && <ConfirmDeleteUserButton id={u.id} />}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      <p className="text-xs text-ink/50">
        Changes auto-save. Flip <strong>Is leader</strong> to <em>yes</em> to make someone available in the <em>Reports to</em> dropdown and on the Organizational Chart.
      </p>
    </div>
  );
}
