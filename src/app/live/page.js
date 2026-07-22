import FacebookEmbed from '@/components/FacebookEmbed';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';
import ConfirmDeleteLiveButton from '@/components/ConfirmDeleteLiveButton';
import { IconVideo } from '@/components/Icons';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Live — Amazing Church Philippines' };

// Convert a share URL into an embeddable player URL.
// - Facebook: needs the canonical Page-video permalink; share links (fb.watch, /share/…) won't embed.
// - YouTube: supports watch/short/embed/youtu.be/live variants.
function fbEmbedUrl(url) {
  if (!url) return null;

  // YouTube — most reliable across variants
  if (/(youtu\.be|youtube\.com)/.test(url)) {
    const id = url.match(/(?:v=|youtu\.be\/|shorts\/|embed\/|live\/)([\w-]{6,})/)?.[1];
    return id ? `https://www.youtube.com/embed/${id}` : null;
  }

  // Facebook Page video permalinks
  if (/^https?:\/\/(www\.|web\.|m\.)?facebook\.com/.test(url)) {
    // Normalize m./web. → www.
    const normalized = url.replace(/^https?:\/\/(?:m|web)\.facebook\.com/, 'https://www.facebook.com');
    return 'https://www.facebook.com/plugins/video.php?href=' + encodeURIComponent(normalized) + '&show_text=false&width=560';
  }

  return url;
}

export default async function Live() {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();
  const [{ data: videos }, { data: series }] = await Promise.all([
    supabase.from('live_videos').select('*').order('occurred_on', { ascending: false }).limit(60),
    supabase.from('live_series').select('*').order('title'),
  ]);

  const canManage = isStaff(profile?.role);
  const seriesList = series || [];
  const seriesById = new Map(seriesList.map(s => [s.id, s]));

  // Group videos by series (nulls into "Uncategorized")
  const grouped = new Map();
  (videos || []).forEach(v => {
    const key = v.series_id || '__none__';
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(v);
  });

  // Order: named series first (alpha), then uncategorized
  const orderedKeys = [
    ...seriesList.filter(s => grouped.has(s.id)).map(s => s.id),
    ...(grouped.has('__none__') ? ['__none__'] : []),
  ];

  return (
    <div className="space-y-10">
      <div className="text-center">
        <h1 className="text-3xl">Watch Live</h1>
        <p className="text-ink/60 mt-2">
          When we go live on Facebook, the stream appears here automatically.
        </p>
      </div>
      <FacebookEmbed tabs="timeline" height={680} showLive />

      <section>
        <div className="flex items-end justify-between gap-4 flex-wrap mb-3">
          <div>
            <h2 className="text-2xl">Previous services</h2>
            <p className="text-sm text-ink/60">Watch what you missed — grouped by series.</p>
          </div>
          <span className="badge bg-silver-light">{videos?.length || 0} in archive</span>
        </div>

        {canManage && (
          <div className="space-y-4 mb-8">
            {/* Series manager */}
            <details className="card">
              <summary className="cursor-pointer font-semibold text-brand">+ Manage series</summary>
              <form action="/api/admin/live-series" method="post"
                className="mt-4 grid sm:grid-cols-[1fr_1fr_auto] gap-3 items-end">
                <div>
                  <label className="label">Series title</label>
                  <input className="input" name="title" required placeholder="Sunday Sermons 2026" />
                </div>
                <div>
                  <label className="label">Cover image URL (optional)</label>
                  <input className="input" name="cover_url" placeholder="https://…" />
                </div>
                <button className="btn-primary">Save series</button>
                <div className="sm:col-span-3">
                  <label className="label">Description (optional)</label>
                  <textarea className="input min-h-[60px]" name="description"
                    placeholder="A short description of this series" />
                </div>
              </form>

              {seriesList.length > 0 && (
                <ul className="mt-4 space-y-2">
                  {seriesList.map(s => (
                    <li key={s.id} className="flex items-center justify-between gap-3 border-t border-silver-light pt-3">
                      <div>
                        <p className="font-medium">{s.title}</p>
                        {s.description && <p className="text-xs text-ink/60">{s.description}</p>}
                      </div>
                      <form action="/api/admin/live-series" method="post">
                        <input type="hidden" name="action" value="delete" />
                        <input type="hidden" name="id" value={s.id} />
                        <button className="text-xs text-red-700 hover:underline">Delete</button>
                      </form>
                    </li>
                  ))}
                </ul>
              )}
            </details>

            {/* Add a video */}
            <details className="card" open>
              <summary className="cursor-pointer font-semibold text-brand">+ Add a video to the archive</summary>
              <form action="/api/admin/live-videos" method="post"
                className="mt-4 grid sm:grid-cols-[1fr_1fr_10rem_1fr_auto] gap-3 items-end">
                <div>
                  <label className="label">Title</label>
                  <input className="input" name="title" required placeholder="Sunday Service — Faith in Action" />
                </div>
                <div>
                  <label className="label">Video URL</label>
                  <input className="input" name="video_url" required placeholder="Facebook Page video permalink or YouTube URL" />
                  <p className="text-[11px] text-ink/50 mt-1">
                    Facebook embeds only work for videos posted from a Page. Use the video's canonical URL
                    (<code>facebook.com/&lt;PageName&gt;/videos/&lt;id&gt;</code>) — <em>not</em> a share/fb.watch link.
                    YouTube works out of the box.
                  </p>
                </div>
                <div>
                  <label className="label">Date</label>
                  <input className="input" name="occurred_on" required type="date" />
                </div>
                <div>
                  <label className="label">Series</label>
                  <select className="input" name="series_id" defaultValue="">
                    <option value="">— none —</option>
                    {seriesList.map(s => <option key={s.id} value={s.id}>{s.title}</option>)}
                  </select>
                </div>
                <button className="btn-primary">Add</button>
              </form>
            </details>
          </div>
        )}

        {orderedKeys.length === 0 ? (
          <div className="card text-center text-ink/60 py-10">
            <div className="text-brand inline-block"><IconVideo size={40} /></div>
            <p className="mt-2">No previous services in the archive yet.</p>
          </div>
        ) : orderedKeys.map(key => {
          const items = grouped.get(key);
          const s = key === '__none__' ? null : seriesById.get(key);
          return (
            <div key={key} className="mb-10">
              <div className="flex items-end justify-between gap-3 mb-3">
                <div>
                  <h3 className="text-xl">
                    {s ? s.title : 'Uncategorized'}
                  </h3>
                  {s?.description && <p className="text-sm text-ink/60">{s.description}</p>}
                </div>
                <span className="text-xs text-ink/50">{items.length} video{items.length === 1 ? '' : 's'}</span>
              </div>
              <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
                {items.map(v => {
                  const embed = fbEmbedUrl(v.video_url);
                  return (
                    <article key={v.id} className="card p-0 overflow-hidden">
                      <div className="aspect-video bg-black">
                        {embed ? (
                          <iframe src={embed} className="w-full h-full" allowFullScreen
                            allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share"
                            title={v.title} />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-white/70 text-sm">
                            Preview unavailable
                          </div>
                        )}
                      </div>
                      <div className="p-4">
                        <p className="text-xs uppercase tracking-wider text-brand font-semibold">
                          {new Date(v.occurred_on).toLocaleDateString(undefined, { year:'numeric', month:'long', day:'numeric' })}
                        </p>
                        <h4 className="text-lg mt-1 leading-snug">{v.title}</h4>
                        <div className="mt-3 flex items-center justify-between text-sm">
                          <a href={v.video_url} target="_blank" rel="noreferrer"
                            className="text-brand hover:underline">Watch on Facebook / YouTube ↗</a>
                          {canManage && <ConfirmDeleteLiveButton id={v.id} />}
                        </div>
                      </div>
                    </article>
                  );
                })}
              </div>
            </div>
          );
        })}
      </section>
    </div>
  );
}
