import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import PostCard from '@/components/PostCard';
import PostComposer from '@/components/PostComposer';
import { isApproved } from '@/lib/roles';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

async function countComments(supabase, entityType, ids) {
  if (!ids.length) return {};
  const { data } = await supabase.from('comments')
    .select('entity_id').eq('entity_type', entityType).in('entity_id', ids);
  const map = {};
  (data || []).forEach(r => { map[r.entity_id] = (map[r.entity_id] || 0) + 1; });
  return map;
}

export default async function Discussions() {
  const { user, profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: threads } = await supabase
    .from('discussions')
    .select('*, author:profiles!discussions_author_id_fkey(full_name, avatar_url)')
    .eq('status', 'approved')
    .order('created_at', { ascending: false })
    .limit(50);

  const commentCounts = await countComments(supabase, 'discussion', threads?.map(t => t.id) || []);

  return (
    <div className="max-w-2xl mx-auto space-y-5">
      <div className="text-center">
        <h1 className="text-3xl">Discussions</h1>
        <p className="text-ink/60 text-sm">Ask, share, and grow together in faith.</p>
      </div>

      {user && isApproved(profile) && <PostComposer kind="discussion" />}
      {user && !isApproved(profile) && (
        <div className="card text-center">
          <p className="text-sm text-ink/70">
            Your account is pending approval. You'll be able to start discussions once an admin approves you.
          </p>
        </div>
      )}
      {!user && (
        <div className="card text-center">
          <p className="text-ink/70">Join the conversation.</p>
          <div className="mt-3 flex justify-center gap-2">
            <Link href="/login" className="btn-outline">Log in</Link>
            <Link href="/signup" className="btn-primary">Sign up</Link>
          </div>
        </div>
      )}

      {threads?.length ? threads.map(t =>
        <PostCard key={t.id} item={t} kind="discussion" viewerRole={profile?.role}
          commentCount={commentCounts[t.id] || 0} />
      ) : <p className="text-ink/60 text-center py-8">No discussions yet.</p>}
    </div>
  );
}
