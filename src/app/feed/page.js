import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import PostCard from '@/components/PostCard';
import PostComposer from '@/components/PostComposer';
import Link from 'next/link';
import { isApproved } from '@/lib/roles';

export const dynamic = 'force-dynamic';

async function countComments(supabase, entityType, ids) {
  if (!ids.length) return {};
  const { data } = await supabase.from('comments')
    .select('entity_id').eq('entity_type', entityType).in('entity_id', ids);
  const map = {};
  (data || []).forEach(r => { map[r.entity_id] = (map[r.entity_id] || 0) + 1; });
  return map;
}

export default async function Feed() {
  const { user, profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: posts } = await supabase
    .from('posts')
    .select('*, author:profiles!posts_author_id_fkey(full_name, avatar_url)')
    .eq('status', 'approved')
    .order('created_at', { ascending: false })
    .limit(50);

  const commentCounts = await countComments(supabase, 'post', posts?.map(p => p.id) || []);

  return (
    <div className="max-w-2xl mx-auto space-y-5">
      <div className="text-center">
        <h1 className="text-3xl">Community Feed</h1>
        <p className="text-ink/60 text-sm">Testimonies, praises, and moments from our church family.</p>
      </div>

      {user && isApproved(profile) && <PostComposer kind="post" />}
      {user && !isApproved(profile) && (
        <div className="card text-center">
          <p className="text-sm text-ink/70">
            Your account is pending approval. You'll be able to share posts as soon as an admin approves you.
          </p>
        </div>
      )}
      {!user && (
        <div className="card text-center">
          <p className="text-ink/70">Want to share something with the community?</p>
          <div className="mt-3 flex justify-center gap-2">
            <Link href="/login" className="btn-outline">Log in</Link>
            <Link href="/signup" className="btn-primary">Sign up</Link>
          </div>
        </div>
      )}

      {posts?.length ? posts.map(p =>
        <PostCard key={p.id} item={p} kind="post" viewerRole={profile?.role}
          commentCount={commentCounts[p.id] || 0} />
      ) : <p className="text-ink/60 text-center py-8">No posts yet — be the first to share something.</p>}
    </div>
  );
}
