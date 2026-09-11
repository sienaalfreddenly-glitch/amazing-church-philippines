import Link from 'next/link';
import { notFound } from 'next/navigation';
import Avatar from '@/components/Avatar';
import Reveal from '@/components/Reveal';
import SocialLinks from '@/components/SocialLinks';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';
import { eventDate } from '@/lib/format';

/**
 * Who has volunteered for one ministry.
 *
 * Row-level security already limits this table to the ministry's own leader and
 * to staff, so a member reaching this URL sees an empty list rather than other
 * people's names. The explicit check below is so they get an honest message
 * instead of a page that looks broken.
 */

export async function generateMetadata({ params }) {
  return { title: `Interested · ${params.slug.replace(/-/g, ' ')}` };
}

export default async function InterestedPage({ params }) {
  const { user, profile } = await getSessionAndProfile();
  const supabase = createClient();

  const { data: ministry } = await supabase
    .from('ministries')
    .select('id, slug, name, summary, leader_id')
    .eq('slug', params.slug)
    .single();

  if (!ministry) notFound();

  const allowed = isStaff(profile?.role) || (user && ministry.leader_id === user.id);

  if (!allowed) {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">{ministry.name}</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          This list is for the leaders of this ministry. If you volunteered, one of them
          will speak with you.
        </p>
        <Link href="/ministries" className="btn-primary mt-8">Back to ministries</Link>
      </section>
    );
  }

  const { data: interests } = await supabase
    .from('ministry_interests')
    .select('id, created_at, note, profile:profiles(id, full_name, avatar_url, email, title, facebook_url, instagram_url)')
    .eq('ministry_id', ministry.id)
    .order('created_at', { ascending: false });

  // Phone numbers are not readable through the profiles table, so they come
  // from the function that decides who may see which.
  const { data: contacts } = await supabase.rpc('visible_contacts');
  const contactById = new Map((contacts || []).map((c) => [c.id, c.contact_number]));

  const rows = interests || [];

  return (
    <div className="space-y-8">
      <Reveal>
        <header>
          <Link href="/ministries" className="btn-quiet -ml-2 mb-6">Back to ministries</Link>
          <h1 className="text-4xl sm:text-5xl">{ministry.name}</h1>
          <p className="mt-2 text-ink/60">{ministry.summary}</p>
          <p className="nums mt-4 text-sm font-medium text-brand">
            {rows.length} {rows.length === 1 ? 'person has' : 'people have'} put their hand up
          </p>
          <hr className="gilt-rule mt-5" />
        </header>
      </Reveal>

      {rows.length ? (
        <ul className="space-y-3">
          {rows.map((row, i) => (
            <Reveal key={row.id} delay={i * 60} as="li">
              <div className="card flex flex-wrap items-center gap-4">
                <Avatar url={row.profile?.avatar_url} name={row.profile?.full_name} size={44} />

                <div className="min-w-0 flex-1">
                  <p className="font-medium">{row.profile?.full_name}</p>
                  {row.profile?.title && (
                    <p className="text-xs text-ink/50">{row.profile.title}</p>
                  )}
                  <SocialLinks
                    profile={{ ...row.profile, contact_number: contactById.get(row.profile?.id) }}
                    className="mt-1.5"
                  />
                  {row.note && <p className="mt-2 text-sm text-ink/65">{row.note}</p>}
                </div>

                <p className="nums shrink-0 text-xs text-ink/45">{eventDate(row.created_at)}</p>
              </div>
            </Reveal>
          ))}
        </ul>
      ) : (
        <div className="card card-static py-12 text-center text-ink/60">
          <p className="font-medium text-ink/75">Nobody has volunteered yet</p>
          <p className="mx-auto mt-1 max-w-sm text-sm">
            Mention it from the front, or speak to someone you have already noticed doing this
            without being asked.
          </p>
        </div>
      )}
    </div>
  );
}
