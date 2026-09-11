import Link from 'next/link';
import Avatar from './Avatar';
import ModerationActions from './ModerationActions';
import ReactionBar from './ReactionBar';
import CommentsSection from './CommentsSection';
import TimeAgo from './TimeAgo';
import { RenderMentions } from './MentionInput';
import DeletePostButton from './DeletePostButton';
import { isStaff } from '@/lib/roles';

/**
 * A post in the feed, or a thread in the discussions list.
 *
 * variant "full"    the whole body with reactions and comments, used in the feed
 * variant "preview" title-led with an excerpt, used for the discussions list
 *
 * The two need different shapes. A feed post is the thing itself and is read in
 * place. A discussion is a question with a conversation under it, so the list
 * should show what is being asked and how busy it is, not dump every thread's
 * full text into one scroll.
 */

function Media({ url, authorName }) {
  if (!url) return null;
  const isVideo = /\.(mp4|webm|mov)$/i.test(url);

  return (
    <div className="mt-4 overflow-hidden rounded-xl bg-silver-light">
      {isVideo ? (
        <video src={url} controls preload="metadata" className="w-full" />
      ) : (
        // Lazy, and async decoding, so a long feed does not fetch and decode
        // every image before the first one is readable.
        <img
          src={url}
          alt={`Shared by ${authorName || 'a member'}`}
          loading="lazy"
          decoding="async"
          className="w-full"
        />
      )}
    </div>
  );
}

function Byline({ item, size = 40 }) {
  return (
    <div className="flex items-center gap-3">
      <Avatar url={item.author?.avatar_url} name={item.author?.full_name || ''} size={size} />
      <div className="min-w-0">
        <p className="truncate text-sm font-medium">{item.author?.full_name || 'Member'}</p>
        <p className="text-xs text-ink/50"><TimeAgo date={item.created_at} /></p>
      </div>
    </div>
  );
}

export default function PostCard({
  item,
  kind,
  viewerRole,
  viewerId,
  commentCount = 0,
  variant = 'full',
}) {
  const showMod = isStaff(viewerRole);
  const canDelete = viewerId && (viewerId === item.author_id || isStaff(viewerRole));
  const entityType = kind === 'discussion' ? 'discussion' : 'post';

  if (variant === 'preview') {
    return (
      <article className="card group">
        <div className="flex items-start justify-between gap-4">
          <Byline item={item} size={36} />
          {canDelete && <DeletePostButton id={item.id} kind={kind} />}
        </div>

        <h2 className="mt-4 text-xl leading-snug transition-colors group-hover:text-brand sm:text-2xl">
          <Link href={`/discussions/${item.id}`} className="after:absolute after:inset-0">
            {item.title || 'Untitled'}
          </Link>
        </h2>

        {item.body && (
          <p className="mt-2 line-clamp-3 text-ink/65">
            <RenderMentions body={item.body} />
          </p>
        )}

        <p className="nums card-foot text-sm font-medium text-brand">
          {commentCount === 0
            ? 'No replies yet'
            : `${commentCount} ${commentCount === 1 ? 'reply' : 'replies'}`}
        </p>
      </article>
    );
  }

  return (
    <article className="card">
      <header className="flex items-start justify-between gap-4">
        <Byline item={item} />
        <div className="flex shrink-0 items-center gap-2">
          {item.status !== 'approved' && (
            <span className={`badge ${
              item.status === 'pending' ? 'bg-silver-light text-ink/70' : 'bg-brand-100 text-brand-800'
            }`}>{item.status}</span>
          )}
          {canDelete && <DeletePostButton id={item.id} kind={kind} />}
        </div>
      </header>

      {item.title && <h2 className="mt-4 text-xl sm:text-2xl">{item.title}</h2>}

      <div className="mt-3 whitespace-pre-wrap leading-relaxed text-ink/85">
        <RenderMentions body={item.body} />
      </div>

      <Media url={item.media_url} authorName={item.author?.full_name} />

      {item.status === 'approved' && (
        <>
          <div className="mt-5">
            <ReactionBar entityType={entityType} entityId={item.id} commentCount={commentCount} />
          </div>

          {/* Comments are folded away by default. Open, they mounted a live
              subscription for every post on screen at once, which made a long
              feed heavy before a single comment had been read. */}
          <details className="mt-4 border-t border-silver-light pt-4">
            <summary className="cursor-pointer list-none text-sm font-medium text-ink/70 transition-colors hover:text-brand">
              {commentCount === 0
                ? 'Add a comment'
                : `${commentCount} ${commentCount === 1 ? 'comment' : 'comments'}`}
            </summary>
            <div className="mt-4">
              <CommentsSection entityType={entityType} entityId={item.id} />
            </div>
          </details>
        </>
      )}

      {showMod && item.status !== 'approved' && (
        <ModerationActions kind={kind} id={item.id} status={item.status} />
      )}
    </article>
  );
}
