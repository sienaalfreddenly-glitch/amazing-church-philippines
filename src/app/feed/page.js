import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import PostCard from '@/components/PostCard';
import PostComposer from '@/components/PostComposer';
import MembersOnlyGate from '@/components/MembersOnlyGate';
import PageHeader from '@/components/PageHeader';
import Reveal from '@/components/Reveal';
import { IconCamera } from '@/components/Icons';
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

  // Everything below this line is for approved members, so the page no longer
  // carries branches for signed-out or pending readers. They were unreachable,
  // and one of them referenced a component that was never imported.
  if (!user || !isApproved(profile)) {
    return (
      <MembersOnlyGate
        title="Feed"
        description="Read what God is doing in the lives of people here, and share your own."
      />
    );
  }

  const supabase = createClient();
  const { data: posts } = await supabase
    .from('posts')
    .select('*, author:profiles!posts_author_id_fkey(full_name, avatar_url)')
    .eq('status', 'approved')
    .order('created_at', { ascending: false })
    .limit(50);

  const commentCounts = await countComments(supabase, 'post', posts?.map(p => p.id) || []);
  const items = posts || [];

  return (
    <div className="stack-l">
      <PageHeader
        eyebrow="Together"
        title="Feed"
        lead="Answered prayers, hard weeks, small wins. Post whatever God is doing in your life, and read what he is doing in someone else's."
      />

      {/* The reading column is narrower than the page. Full-width posts on a
          wide monitor give lines nobody can track back from. */}
      <div className="shell-narrow stack">
        <PostComposer kind="post" />

        {items.length ? (
          items.map((p, i) => (
            <Reveal key={p.id} delay={Math.min(i, 4) * 70}>
              <PostCard
                item={p}
                kind="post"
                viewerRole={profile?.role}
                viewerId={user?.id}
                commentCount={commentCounts[p.id] || 0}
              />
            </Reveal>
          ))
        ) : (
          <div className="card card-static py-14 text-center">
            <div className="inline-block animate-floaty text-brand"><IconCamera size={40} /></div>
            <p className="mt-4 font-medium text-ink/75">Nothing here yet</p>
            <p className="mx-auto mt-1 max-w-xs text-sm text-ink/60">
              Somebody has to go first. A sentence about your week is plenty.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
