import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import PostCard from '@/components/PostCard';
import PostComposer from '@/components/PostComposer';
import MembersOnlyGate from '@/components/MembersOnlyGate';
import PageHeader from '@/components/PageHeader';
import Reveal from '@/components/Reveal';
import { IconChat } from '@/components/Icons';
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

export default async function Discussions() {
  const { user, profile } = await getSessionAndProfile();

  if (!user || !isApproved(profile)) {
    return (
      <MembersOnlyGate
        title="Discussions"
        description="Bring your questions about faith and life, and talk them through with the church."
      />
    );
  }

  const supabase = createClient();
  const { data: threads } = await supabase
    .from('discussions')
    .select('*, author:profiles!discussions_author_id_fkey(full_name, avatar_url)')
    .eq('status', 'approved')
    .order('created_at', { ascending: false })
    .limit(50);

  const commentCounts = await countComments(supabase, 'discussion', threads?.map(t => t.id) || []);
  const items = threads || [];

  // Threads nobody has answered yet come first. An unanswered question in a
  // church is the one thing on this page that actually needs someone.
  const unanswered = items.filter((t) => !commentCounts[t.id]);
  const answered = items.filter((t) => commentCounts[t.id]);

  return (
    <div className="stack-l">
      <PageHeader
        eyebrow="Ask anything"
        title="Discussions"
        lead="Bring the question you have been carrying around. Nobody here expects you to have it all worked out, and no question is too basic to ask."
      />

      <div className="shell-narrow stack">
        <PostComposer kind="discussion" />

        {!items.length && (
          <div className="card card-static py-14 text-center">
            <div className="inline-block animate-floaty text-brand"><IconChat size={40} /></div>
            <p className="mt-4 font-medium text-ink/75">No questions yet</p>
            <p className="mx-auto mt-1 max-w-xs text-sm text-ink/60">
              Ask the first one. Whatever it is, somebody else is wondering it too.
            </p>
          </div>
        )}

        {unanswered.length > 0 && (
          <section aria-labelledby="unanswered-heading" className="stack">
            <h2 id="unanswered-heading" className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink/50">
              Waiting for a reply
            </h2>
            {unanswered.map((t, i) => (
              <Reveal key={t.id} delay={Math.min(i, 4) * 70}>
                <div className="relative">
                  <PostCard
                    item={t}
                    kind="discussion"
                    variant="preview"
                    viewerRole={profile?.role}
                    viewerId={user?.id}
                    commentCount={0}
                  />
                </div>
              </Reveal>
            ))}
          </section>
        )}

        {answered.length > 0 && (
          <section aria-labelledby="answered-heading" className="stack">
            <h2 id="answered-heading" className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink/50">
              Being talked about
            </h2>
            {answered.map((t, i) => (
              <Reveal key={t.id} delay={Math.min(i, 4) * 70}>
                <div className="relative">
                  <PostCard
                    item={t}
                    kind="discussion"
                    variant="preview"
                    viewerRole={profile?.role}
                    viewerId={user?.id}
                    commentCount={commentCounts[t.id] || 0}
                  />
                </div>
              </Reveal>
            ))}
          </section>
        )}
      </div>
    </div>
  );
}
