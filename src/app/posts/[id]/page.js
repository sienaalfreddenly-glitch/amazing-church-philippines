import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import ReactionBar from '@/components/ReactionBar';
import CommentsSection from '@/components/CommentsSection';
import ModerationActions from '@/components/ModerationActions';
import Avatar from '@/components/Avatar';
import TimeAgo from '@/components/TimeAgo';
import { isStaff } from '@/lib/roles';
import { notFound } from 'next/navigation';

export const dynamic = 'force-dynamic';

export default async function PostDetail({ params }) {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: post } = await supabase.from('posts')
    .select('*, author:profiles!posts_author_id_fkey(full_name, avatar_url)')
    .eq('id', params.id).single();
  if (!post) notFound();

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <article className="card">
        <div className="flex items-center gap-3">
          <Avatar url={post.author?.avatar_url} name={post.author?.full_name || ''} size={40} />
          <div>
            <p className="font-medium">{post.author?.full_name}</p>
            <p className="text-xs text-ink/50"><TimeAgo date={post.created_at} /></p>
          </div>
        </div>
        {post.title && <h1 className="text-2xl mt-4">{post.title}</h1>}
        <p className="mt-3 whitespace-pre-wrap">{post.body}</p>
        {post.media_url && (
          <div className="mt-3">
            {/\.(mp4|webm)$/i.test(post.media_url)
              ? <video src={post.media_url} controls className="w-full rounded-lg" />
              : <img src={post.media_url} alt="" className="w-full rounded-lg" />}
          </div>
        )}
        <div className="mt-4"><ReactionBar entityType="post" entityId={post.id} /></div>
        {isStaff(profile?.role) &&
          <ModerationActions kind="post" id={post.id} status={post.status} />}
      </article>
      <div className="card"><CommentsSection entityType="post" entityId={post.id} /></div>
    </div>
  );
}
