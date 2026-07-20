import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isStaff, isAdmin } from '@/lib/roles';
import ModerationActions from '@/components/ModerationActions';
import TimeAgo from '@/components/TimeAgo';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function AdminHome() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isStaff(profile.role)) redirect('/');

  const supabase = createClient();
  const [{ data: pendingPosts }, { data: pendingDiscussions }, { data: pendingUsers }] = await Promise.all([
    supabase.from('posts').select('*, author:profiles!posts_author_id_fkey(full_name)').eq('status','pending').order('created_at'),
    supabase.from('discussions').select('*, author:profiles!discussions_author_id_fkey(full_name)').eq('status','pending').order('created_at'),
    supabase.from('profiles').select('*').eq('account_status','pending').order('created_at'),
  ]);

  return (
    <div className="space-y-10">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl">Moderation</h1>
          <p className="text-ink/60 text-sm">Signed in as {profile.full_name} · {profile.role.replace('_',' ')}</p>
        </div>
        {isAdmin(profile.role) && <Link href="/admin/users" className="btn-primary">Manage users</Link>}
      </div>

      {isAdmin(profile.role) && (
        <section>
          <h2 className="text-2xl mb-3">Pending accounts ({pendingUsers?.length || 0})</h2>
          <div className="space-y-3">
            {pendingUsers?.length ? pendingUsers.map(u => (
              <div key={u.id} className="card flex items-center justify-between">
                <div>
                  <p className="font-medium">{u.full_name}</p>
                  <p className="text-sm text-ink/60">{u.email}</p>
                </div>
                <UserApproveButtons id={u.id} />
              </div>
            )) : <p className="text-ink/60 text-sm">Nothing pending.</p>}
          </div>
        </section>
      )}

      <section>
        <h2 className="text-2xl mb-3">Pending posts ({pendingPosts?.length || 0})</h2>
        <div className="space-y-3">
          {pendingPosts?.length ? pendingPosts.map(p => (
            <div key={p.id} className="card">
              <p className="text-xs uppercase text-ink/50">{p.author?.full_name} · <TimeAgo date={p.created_at} /></p>
              {p.title && <h3 className="text-lg mt-1">{p.title}</h3>}
              <p className="mt-2 whitespace-pre-wrap">{p.body}</p>
              <ModerationActions kind="post" id={p.id} status={p.status} />
            </div>
          )) : <p className="text-ink/60 text-sm">Nothing pending.</p>}
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
          )) : <p className="text-ink/60 text-sm">Nothing pending.</p>}
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
