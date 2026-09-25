import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin, roleLabel, statusLabel, nextPromotionFor, householdLabel } from '@/lib/roles';
import Avatar from '@/components/Avatar';
import AutoForm from '@/components/AutoForm';
import PageHeader from '@/components/PageHeader';
import ConfirmDeleteUserButton from '@/components/ConfirmDeleteUserButton';
import SetTempPasswordButton from '@/components/SetTempPasswordButton';
import { eventDate } from '@/lib/format';

export const dynamic = 'force-dynamic';

/**
 * Members.
 *
 * This was an eight column table that scrolled sideways, which meant the
 * actions at the right hand end were off screen until you dragged the bar.
 * Anything you cannot see you will not use, so each member is now a card that
 * fits whatever width is available, with the controls grouped by what they do:
 * who this person is, what they may do, and the buttons that change their
 * account.
 */
export default async function ManageUsers() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');

  const supabase = createClient();
  const viewerIsSuper = profile.role === 'super_admin';
  const [{ data: users, error }, { data: allCompletions }] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, role, account_status, leader_id, is_leader, title, created_at')
      .order('created_at', { ascending: false }),
    supabase.from('lesson_completions')
      .select('verified_at, enrollment:enrollments(user_id), lesson:course_lessons(title, ord, course:courses(code))')
      .order('verified_at', { ascending: false }),
  ]);

  const { data: contacts } = await supabase.rpc('visible_contacts');
  const contactById = new Map((contacts || []).map(c => [c.id, c.contact_number]));

  // Only two rows ever get filtered out here: the church profile (which is
  // edited from /admin/church, not from the members list), and super-admin
  // rows for anyone who is not themselves a super admin.
  const CHURCH_ID = '11111111-1111-4111-8111-111111111111';
  const list = (users || [])
    .filter(u => u.id !== CHURCH_ID)
    .filter(u => viewerIsSuper || u.role !== 'super_admin');
  const leaders = list.filter(u => u.is_leader);
  const latestByUser = new Map();
  (allCompletions || []).forEach(c => {
    const uid = c.enrollment?.user_id;
    if (!uid || latestByUser.has(uid)) return;
    latestByUser.set(uid, c);
  });

  // Anyone still waiting comes first. They are the only rows that need action.
  const pending = list.filter(u => u.account_status !== 'approved');
  const approved = list.filter(u => u.account_status === 'approved');
  const ordered = [...pending, ...approved];

  return (
    <div className="stack">
      <PageHeader
        title="Members"
        lead="Roles, approvals, and who looks after whom. Changes save as soon as you make them."
        action={
          <span className="nums badge bg-silver-light text-ink/70">
            {list.length} {list.length === 1 ? 'member' : 'members'}
          </span>
        }
      />

      {error && <p className="field-error">Could not load members: {error.message}</p>}

      {pending.length > 0 && (
        <p className="nums text-sm font-medium text-brand">
          {pending.length} {pending.length === 1 ? 'account is' : 'accounts are'} waiting for approval.
        </p>
      )}

      <div className="stack">
        {ordered.map((u) => {
          const isSelf = u.id === profile.id;
          const isSuper = u.role === 'super_admin';
          const roleLocked = isSuper && profile.role !== 'super_admin';
          const waiting = u.account_status !== 'approved';
          const lesson = latestByUser.get(u.id);

          return (
            <article key={u.id} className={`card ${waiting ? 'ring-1 ring-brand/30' : ''}`}>
              {/* Who this is */}
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex min-w-0 items-center gap-3">
                  <Avatar url={u.avatar_url} name={u.full_name} size={44} />
                  <div className="min-w-0">
                    <p className="flex flex-wrap items-center gap-2 font-medium">
                      {u.full_name}
                      {isSelf && <span className="badge bg-silver-light text-ink/60">You</span>}
                    </p>
                    <p className="truncate text-sm text-ink/55">{u.email}</p>
                    <p className="nums mt-0.5 text-xs text-ink/45">
                      {contactById.get(u.id) || 'No number on file'}
                    </p>
                  </div>
                </div>

                <div className="flex shrink-0 flex-wrap items-center gap-2">
                  <span className="badge bg-brand-50 text-brand-700">{roleLabel(u.role)}</span>
                  <span className={`badge ${
                    u.account_status === 'approved'
                      ? 'bg-silver-light text-ink/60'
                      : 'bg-brand text-white'
                  }`}>
                    {statusLabel(u.account_status)}
                  </span>
                  {waiting && (
                    <form action="/api/admin/approve-user" method="post">
                      <input type="hidden" name="id" value={u.id} />
                      <input type="hidden" name="action" value="approve" />
                      <button className="btn-primary">Approve</button>
                    </form>
                  )}
                </div>
              </div>

              {/* What they may do */}
              <div className="mt-5 grid gap-4 border-t border-silver-light pt-4 sm:grid-cols-3">
                <AutoForm action="/api/admin/set-role">
                  <input type="hidden" name="id" value={u.id} />
                  <label className="label" htmlFor={`role-${u.id}`}>Role</label>
                  <select
                    id={`role-${u.id}`}
                    name="role"
                    defaultValue={u.role}
                    disabled={roleLocked}
                    className="input"
                  >
                    <option value="user">Member</option>
                    <option value="moderator">Moderator</option>
                    <option value="admin">Admin</option>
                    {profile.role === 'super_admin' && <option value="super_admin">Super Admin</option>}
                  </select>
                  {roleLocked && (
                    <p className="mt-1 text-xs text-ink/45">Only a Super Admin can change this.</p>
                  )}
                </AutoForm>

                <AutoForm action="/api/admin/set-leader-flag">
                  <input type="hidden" name="id" value={u.id} />
                  <label className="label" htmlFor={`role-church-${u.id}`}>Church role</label>
                  <select
                    id={`role-church-${u.id}`}
                    name="church_role"
                    defaultValue={u.is_leader ? (u.title || 'Leader') : 'Disciple'}
                    className="input"
                  >
                    <option value="Head Pastor">Head Pastor</option>
                    <option value="Pastor">Pastor</option>
                    <option value="Leader">Leader</option>
                    <option value="Disciple">Disciple</option>
                  </select>
                  <p className="mt-1 text-xs text-ink/45">
                    Head Pastor, Pastor and Leader all shepherd a group; a Disciple does not yet.
                  </p>
                </AutoForm>

                <AutoForm action="/api/admin/set-leader">
                  <input type="hidden" name="id" value={u.id} />
                  <label className="label" htmlFor={`reports-${u.id}`}>Shepherded by</label>
                  <select
                    id={`reports-${u.id}`}
                    name="leader_id"
                    defaultValue={u.leader_id || ''}
                    disabled={leaders.length === 0}
                    className="input"
                  >
                    <option value="">Nobody yet</option>
                    {leaders.filter(l => l.id !== u.id).map(l => (
                      <option key={l.id} value={l.id}>{l.full_name}</option>
                    ))}
                  </select>
                  {leaders.length === 0 && (
                    <p className="mt-1 text-xs text-ink/45">Mark somebody as a leader first.</p>
                  )}
                </AutoForm>
              </div>

              {/* Promotion.
                  Silent on rows the viewer cannot promote (either because the
                  target is already at the top of their possible ladder, or
                  because the viewer is not a Head Pastor / Pastor / Leader /
                  Super Admin). The database enforces the same check server
                  side; this is the visible shortcut. */}
              {(() => {
                const next = nextPromotionFor(profile, u);
                if (!next || isSelf) return null;
                return (
                  <form
                    action="/api/admin/promote"
                    method="post"
                    className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-brand-50/60 px-4 py-3 ring-1 ring-brand-100"
                  >
                    <input type="hidden" name="id" value={u.id} />
                    <input type="hidden" name="to" value={next} />
                    <p className="text-sm text-ink/70">
                      Now a <strong>{householdLabel(u)}</strong>. Ready to shepherd more?
                    </p>
                    <button className="btn-primary">Promote to {next}</button>
                  </form>
                );
              })()}

              {/* Account actions and progress */}
              <div className="mt-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-3 border-t border-silver-light pt-4">
                <p className="text-xs text-ink/50">
                  {lesson ? (
                    <>
                      Last lesson{' '}
                      <span className="font-semibold text-brand">{lesson.lesson?.course?.code}</span>{' '}
                      L{lesson.lesson?.ord} · {lesson.lesson?.title}
                      <span className="nums"> · {eventDate(lesson.verified_at, { hour: undefined, minute: undefined })}</span>
                    </>
                  ) : (
                    'No lessons verified yet'
                  )}
                </p>

                <div className="flex flex-wrap items-center gap-2">
                  <form action="/api/admin/reset-password" method="post">
                    <input type="hidden" name="id" value={u.id} />
                    <button className="btn-quiet" title="Send a password reset email">
                      Email reset
                    </button>
                  </form>
                  <SetTempPasswordButton id={u.id} name={u.full_name} />
                  {!isSelf && !roleLocked && <ConfirmDeleteUserButton id={u.id} />}
                </div>
              </div>
            </article>
          );
        })}
      </div>
    </div>
  );
}
