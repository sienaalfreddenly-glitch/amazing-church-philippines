import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import Link from 'next/link';
import NewsForm from '@/components/NewsForm';

export const dynamic = 'force-dynamic';

const dtLocal = (v) => v ? new Date(v).toISOString().slice(0, 16) : '';

export default async function ManageNews() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');

  const supabase = createClient();
  const { data: posts } = await supabase.from('news_posts')
    .select('*').order('published_at', { ascending: false });
  const list = posts || [];

  return (
    <div className="space-y-8">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-3xl">News & Updates</h1>
          <p className="text-ink/60 text-sm">Publish announcements, articles, and media for the community.</p>
        </div>
        <Link href="/news" className="btn-outline text-xs">View public page →</Link>
      </div>

      <details className="card" open>
        <summary className="cursor-pointer font-semibold text-brand">+ Publish new</summary>
        <NewsForm />
      </details>

      <section className="space-y-3">
        <h2 className="text-xl">Published ({list.length})</h2>
        {list.length === 0 && <p className="text-sm text-ink/60">Nothing published yet.</p>}
        {list.map(p => (
          <details key={p.id} className="card">
            <summary className="cursor-pointer flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs uppercase tracking-wider text-brand font-semibold">
                  {new Date(p.published_at).toLocaleDateString()}
                </p>
                <p className="font-semibold text-lg">{p.title}</p>
              </div>
              <span className="text-xs text-ink/50">click to edit</span>
            </summary>
            <div className="mt-4 border-t border-silver-light pt-4">
              <NewsForm post={p} />
              <form action="/api/admin/news/delete" method="post" className="mt-3 flex justify-end">
                <input type="hidden" name="id" value={p.id} />
                <button className="btn-danger text-xs">Delete</button>
              </form>
            </div>
          </details>
        ))}
      </section>
    </div>
  );
}
