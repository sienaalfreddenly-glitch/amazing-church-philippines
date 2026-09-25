import Link from 'next/link';
import { getSessionAndProfile } from '@/lib/supabase-server';
import { getAllContent } from '@/lib/content';

// Copy the church speaks in belongs to the church. Only super_admin edits it,
// even though other admins can reach the tab, so the page itself is the
// authoritative gate.
export default async function AdminContent() {
  const { profile } = await getSessionAndProfile();
  if (profile?.role !== 'super_admin') {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">Super admins only</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          Site copy is edited by the super admin so the words the church speaks
          in stay under one signature. Ask them if it needs a change.
        </p>
        <Link href="/admin" className="btn-primary mt-8">Back to admin</Link>
      </section>
    );
  }

  const blocks = await getAllContent();
  const groups = blocks.reduce((acc, b) => {
    (acc[b.group] ??= []).push(b);
    return acc;
  }, {});

  return (
    <div className="stack">
      <header>
        <h1 className="text-3xl">Site copy</h1>
        <p className="mt-2 max-w-prose text-ink/65">
          Every editable block is listed below. Leaving a field empty falls back
          to the built-in default, so a block can be reset by clearing it and
          saving. Changes go live on the next page load.
        </p>
      </header>

      {Object.entries(groups).map(([group, items]) => (
        <section key={group} aria-labelledby={`grp-${group}`} className="card card-body">
          <h2 id={`grp-${group}`} className="text-xl">{group}</h2>
          <ul className="mt-6 space-y-6">
            {items.map((b) => (
              <li key={b.slug}>
                <form action="/api/admin/content/upsert" method="post" className="space-y-2">
                  <input type="hidden" name="slug" value={b.slug} />
                  <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                    <label className="label" htmlFor={`c-${b.slug}`}>{b.label}</label>
                    <code className="nums text-[11px] text-ink/40">{b.slug}</code>
                  </div>
                  {b.kind === 'multiline' ? (
                    <textarea
                      id={`c-${b.slug}`}
                      name="body"
                      rows={Math.min(10, Math.max(3, Math.ceil((b.body || b.fallback).length / 80)))}
                      defaultValue={b.body}
                      placeholder={b.fallback}
                      className="input font-sans"
                    />
                  ) : (
                    <input
                      id={`c-${b.slug}`}
                      name="body"
                      type="text"
                      defaultValue={b.body}
                      placeholder={b.fallback}
                      className="input"
                    />
                  )}
                  <div className="flex items-center justify-between gap-4">
                    <p className="text-xs text-ink/45">
                      {b.hasOverride ? 'Custom copy is live.' : 'Using the built-in default.'}
                    </p>
                    <button type="submit" className="btn-primary">Save</button>
                  </div>
                </form>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
