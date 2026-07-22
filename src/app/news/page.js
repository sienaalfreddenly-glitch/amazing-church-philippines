import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isAdmin } from '@/lib/roles';
import Link from 'next/link';
import TimeAgo from '@/components/TimeAgo';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'News & Updates — Amazing Church Philippines' };

function fbEmbedUrl(url) {
  if (!url) return null;
  if (/(youtu\.be|youtube\.com)/.test(url)) {
    const id = url.match(/(?:v=|youtu\.be\/|shorts\/|embed\/|live\/)([\w-]{6,})/)?.[1];
    return id ? `https://www.youtube.com/embed/${id}` : null;
  }
  if (/^https?:\/\/(www\.|web\.|m\.)?facebook\.com/.test(url)) {
    const norm = url.replace(/^https?:\/\/(?:m|web)\.facebook\.com/, 'https://www.facebook.com');
    return 'https://www.facebook.com/plugins/video.php?href=' + encodeURIComponent(norm) + '&show_text=false';
  }
  return null;
}

export default async function NewsPage() {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: posts } = await supabase.from('news_posts')
    .select('*, author:profiles!news_posts_author_id_fkey(full_name, avatar_url)')
    .order('published_at', { ascending: false }).limit(50);
  const list = posts || [];

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div className="flex items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl">News & Updates</h1>
          <p className="text-ink/60 text-sm">The latest from Amazing Church Philippines.</p>
        </div>
        {isAdmin(profile?.role) && (
          <Link href="/admin/news" className="btn-outline text-xs">Manage</Link>
        )}
      </div>

      {list.length === 0 && (
        <div className="card text-center text-ink/60 py-10">
          Nothing published yet — check back soon.
        </div>
      )}

      {list.map(p => {
        const embed = fbEmbedUrl(p.video_url);
        return (
          <article key={p.id} className="card">
            <header className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs uppercase tracking-wider text-brand font-semibold">
                  {new Date(p.published_at).toLocaleDateString(undefined, { year:'numeric', month:'long', day:'numeric' })}
                </p>
                <h2 className="text-2xl mt-1">{p.title}</h2>
                {p.author?.full_name && (
                  <p className="text-xs text-ink/60 mt-1">
                    by {p.author.full_name} · <TimeAgo date={p.published_at} />
                  </p>
                )}
              </div>
            </header>

            <p className="mt-4 whitespace-pre-wrap text-ink/90 leading-relaxed">{p.body}</p>

            {p.media_urls?.length > 0 && (
              <div className={`mt-4 grid gap-2 ${p.media_urls.length === 1 ? 'grid-cols-1' : 'grid-cols-2'}`}>
                {p.media_urls.map((u, i) => (
                  <div key={i} className="rounded-xl overflow-hidden border border-silver-light bg-black/5">
                    {/\.(mp4|webm|mov)$/i.test(u)
                      ? <video src={u} controls className="w-full" />
                      : <img src={u} alt="" className="w-full object-cover" />}
                  </div>
                ))}
              </div>
            )}

            {embed && (
              <div className="mt-4 aspect-video rounded-xl overflow-hidden bg-black">
                <iframe src={embed} className="w-full h-full" allowFullScreen title={p.title}
                  allow="autoplay; clipboard-write; encrypted-media; picture-in-picture" />
              </div>
            )}
          </article>
        );
      })}
    </div>
  );
}
