import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isStaff, isAdmin } from '@/lib/roles';
import ModerationActions from '@/components/ModerationActions';
import TimeAgo from '@/components/TimeAgo';
import Link from 'next/link';
import PageHeader from '@/components/PageHeader';

export const dynamic = 'force-dynamic';

export default async function AdminHome() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isStaff(profile.role)) redirect('/');

  const supabase = createClient();
  const [{ data: pendingPosts }, { data: pendingDiscussions }, { data: pendingUsers }] = await Promise.all([
    supabase.from('posts').select('*, author:profiles!posts_author_id_fkey(full_name)').eq('status','pending').order('created_at'),
    supabase.from('discussions').select('*, author:profiles!discussions_author_id_fkey(full_name)').eq('status','pending').order('created_at'),
    supabase.from('profiles').select('id, full_name, email, role, account_status, avatar_url, leader_id, created_at, is_leader, must_change_password, facebook_url, instagram_url, title, terms_accepted_at, terms_accepted_version').eq('account_status','pending').order('created_at'),
  ]);

  return (
    <div className="stack-l">
      <PageHeader
        title="Queue"
        lead="Everything waiting on you, in one place. Clear this and the rest of the site looks after itself."
      />

      {isAdmin(profile.role) && (
        <section>
          <h2 className="flex items-center gap-3 text-2xl">
            Accounts waiting
            <span className={`nums badge ${pendingUsers?.length ? 'bg-brand text-white' : 'bg-silver-light text-ink/60'}`}>
              {pendingUsers?.length || 0}
            </span>
          </h2>
          <p className="mt-1 text-sm text-ink/55">
            New people cannot post until somebody here lets them in.
          </p>
          <div className="space-y-3">
            {pendingUsers?.length ? pendingUsers.map(u => (
              <div key={u.id} className="card flex items-center justify-between">
                <div>
                  <p className="font-medium">{u.full_name}</p>
                  <p className="text-sm text-ink/60">{u.email}</p>
                </div>
                <UserApproveButtons id={u.id} />
              </div>
            )) : <div className="card card-static py-10 text-center">
                <p className="font-medium text-ink/75">Nothing waiting</p>
                <p className="mt-1 text-sm text-ink/55">Every account has been dealt with.</p>
              </div>}
          </div>
        </section>
      )}

      <section>
        <h2 className="flex items-center gap-3 text-2xl">
          Posts waiting
          <span className={`nums badge ${pendingPosts?.length ? 'bg-brand text-white' : 'bg-silver-light text-ink/60'}`}>
            {pendingPosts?.length || 0}
          </span>
        </h2>
        <p className="mt-1 mb-3 text-sm text-ink/55">
          Held back until a moderator approves them. Nobody is notified until you do.
        </p>
        <div className="space-y-3">
          {pendingPosts?.length ? pendingPosts.map(p => (
            <div key={p.id} className="card">
              <p className="text-xs uppercase text-ink/50">{p.author?.full_name} · <TimeAgo date={p.created_at} /></p>
              {p.title && <h3 className="text-lg mt-1">{p.title}</h3>}
              <p className="mt-2 whitespace-pre-wrap">{p.body}</p>
              <ModerationActions kind="post" id={p.id} status={p.status} />
            </div>
          )) : <div className="card card-static py-10 text-center">
                <p className="font-medium text-ink/75">Nothing waiting</p>
                <p className="mt-1 text-sm text-ink/55">Every account has been dealt with.</p>
              </div>}
        </div>
      </section>

      <section>
        <h2 className="text-2xl mb-3">Pending discussions ({pendingDiscussions?.length || 0})</h2>
        <div className="space-y-3">
          {pendingDiscussions?.length ? pendingDiscussions.map(d => (
            <div key={d.id} className="card">
              <p className="text-xs uppercase text-ink/50">{d.author?.full_name} · <TimeAgo date={d.created_at} /></p>
              <h3 className="text-lg mt-1">{d.title}</h3>
              <p className="mt-2 whitespace-pre-wrap">{d.body}</p>
              <ModerationActions kind="discussion" id={d.id} status={d.status} />
            </div>
          )) : <div className="card card-static py-10 text-center">
                <p className="font-medium text-ink/75">Nothing waiting</p>
                <p className="mt-1 text-sm text-ink/55">Every account has been dealt with.</p>
              </div>}
        </div>
      </section>
    </div>
  );
}

function UserApproveButtons({ id }) {
  return (
    <form action="/api/admin/approve-user" method="post" className="flex gap-2">
      <input type="hidden" name="id" value={id} />
      <button name="action" value="approve" className="btn-primary text-xs px-3 py-1">Approve</button>
      <button name="action" value="reject"  className="btn-outline text-xs px-3 py-1">Reject</button>
    </form>
  );
}
