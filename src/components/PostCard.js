import Avatar from './Avatar';
import ModerationActions from './ModerationActions';
import ReactionBar from './ReactionBar';
import CommentsSection from './CommentsSection';
import TimeAgo from './TimeAgo';
import { RenderMentions } from './MentionInput';
import DeletePostButton from './DeletePostButton';
import { isStaff } from '@/lib/roles';

export default function PostCard({ item, kind, viewerRole, viewerId, commentCount = 0 }) {
  const showMod = isStaff(viewerRole);
  const canDelete = viewerId && (viewerId === item.author_id || isStaff(viewerRole));
  return (
    <article className="card">
      <header className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Avatar url={item.author?.avatar_url} name={item.author?.full_name || ''} size={40} />
          <div>
            <p className="text-sm font-medium">{item.author?.full_name || 'Member'}</p>
            <p className="text-xs text-ink/50"><TimeAgo date={item.created_at} /></p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {item.status !== 'approved' && (
            <span className={`badge ${
              item.status === 'pending' ? 'bg-silver-light text-ink/70' : 'bg-red-50 text-red-700'
            }`}>{item.status}</span>
          )}
          {canDelete && <DeletePostButton id={item.id} kind={kind} />}
        </div>
      </header>

      {item.title && <h3 className="text-xl mt-4">{item.title}</h3>}
      <p className="mt-3 whitespace-pre-wrap text-ink/90 leading-relaxed">
        <RenderMentions body={item.body} />
      </p>

      {item.media_url && (
        <div className="mt-4">
          {/\.(mp4|webm)$/i.test(item.media_url)
            ? <video src={item.media_url} controls className="w-full rounded-xl" />
            : <img src={item.media_url} alt="" className="w-full rounded-xl" />}
        </div>
      )}

      {item.status === 'approved' && (
        <>
          <div className="mt-5">
            <ReactionBar entityType={kind === 'discussion' ? 'discussion' : 'post'}
              entityId={item.id} commentCount={commentCount} />
          </div>
          <div className="mt-5 pt-5 border-t border-silver-light">
            <CommentsSection entityType={kind === 'discussion' ? 'discussion' : 'post'} entityId={item.id} />
          </div>
        </>
      )}

      {showMod && item.status !== 'approved' && <ModerationActions kind={kind} id={item.id} status={item.status} />}
    </article>
  );
}
