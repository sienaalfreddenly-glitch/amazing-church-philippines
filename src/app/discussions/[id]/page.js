import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import ReactionBar from '@/components/ReactionBar';
import CommentsSection from '@/components/CommentsSection';
import ModerationActions from '@/components/ModerationActions';
import Avatar from '@/components/Avatar';
import TimeAgo from '@/components/TimeAgo';
import { isStaff } from '@/lib/roles';
import { notFound } from 'next/navigation';

export const dynamic = 'force-dynamic';

export default async function DiscussionDetail({ params }) {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: d } = await supabase.from('discussions')
    .select('*, author:profiles!discussions_author_id_fkey(full_name, avatar_url)')
    .eq('id', params.id).single();
  if (!d) notFound();

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <article className="card">
        <div className="flex items-center gap-3">
          <Avatar url={d.author?.avatar_url} name={d.author?.full_name || ''} size={40} />
          <div>
            <p className="font-medium">{d.author?.full_name}</p>
            <p className="text-xs text-ink/50"><TimeAgo date={d.created_at} /></p>
          </div>
        </div>
        <h1 className="text-2xl mt-4">{d.title}</h1>
        <p className="mt-3 whitespace-pre-wrap">{d.body}</p>
        <div className="mt-4"><ReactionBar entityType="discussion" entityId={d.id} /></div>
        {isStaff(profile?.role) &&
          <ModerationActions kind="discussion" id={d.id} status={d.status} />}
      </article>
      <div className="card"><CommentsSection entityType="discussion" entityId={d.id} /></div>
    </div>
  );
}
