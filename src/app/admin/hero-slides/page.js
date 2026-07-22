import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isAdmin } from '@/lib/roles';
import HeroSlideForm from '@/components/HeroSlideForm';

export const dynamic = 'force-dynamic';

export default async function ManageHeroSlides() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isAdmin(profile.role)) redirect('/');

  const supabase = createClient();
  const { data: slides } = await supabase.from('hero_slides').select('*').order('ord');
  const list = slides || [];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl">Home hero slideshow</h1>
        <p className="text-ink/60 text-sm">Rotating background images behind the "Welcome home" hero.</p>
      </div>

      <details className="card" open>
        <summary className="cursor-pointer font-semibold text-brand">+ Add a slide</summary>
        <HeroSlideForm nextOrd={(list[list.length - 1]?.ord || 0) + 1} />
      </details>

      <section className="space-y-4">
        <h2 className="text-xl">Slides ({list.length})</h2>
        {list.length === 0 && <p className="text-sm text-ink/60">No slides yet.</p>}
        <div className="grid sm:grid-cols-2 gap-4">
          {list.map(s => (
            <div key={s.id} className="card p-0 overflow-hidden">
              <div className="aspect-video bg-black/5">
                <img src={s.image_url} alt={s.caption || ''} className="w-full h-full object-cover" />
              </div>
              <div className="p-4">
                <p className="text-xs uppercase tracking-wider text-brand font-semibold">
                  Order {s.ord} · {s.is_active ? 'Active' : 'Hidden'}
                </p>
                {s.caption && <p className="text-sm text-ink/70 mt-1">{s.caption}</p>}
                <details className="mt-3">
                  <summary className="text-sm text-brand cursor-pointer">Edit</summary>
                  <HeroSlideForm slide={s} nextOrd={s.ord} />
                </details>
                <form action="/api/admin/hero-slides/delete" method="post" className="mt-2">
                  <input type="hidden" name="id" value={s.id} />
                  <button className="text-xs text-red-700 hover:underline">Delete</button>
                </form>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
