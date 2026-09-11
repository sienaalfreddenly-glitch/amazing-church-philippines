import Link from 'next/link';
import { notFound } from 'next/navigation';
import Avatar from '@/components/Avatar';
import PageHeader from '@/components/PageHeader';
import Reveal from '@/components/Reveal';
import SocialLinks from '@/components/SocialLinks';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isApproved } from '@/lib/roles';
import { eventDate } from '@/lib/format';

export async function generateMetadata() {
  return { title: 'Who is coming' };
}

/**
 * Who has said they are coming to one event.
 *
 * Open to every approved member, not just leaders. Knowing that other people
 * are going is most of the reason anyone decides to go, and an event is a
 * public gathering rather than a private list.
 */
export default async function GoingPage({ params }) {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();

  const { data: event } = await supabase
    .from('events').select('id, title, starts_at, location')
    .eq('id', params.id).single();

  if (!event) notFound();

  if (!isApproved(profile)) {
    return (
      <section className="mx-auto max-w-md py-16 text-center">
        <h1 className="text-3xl">{event.title}</h1>
        <p className="mx-auto mt-4 max-w-prose text-ink/65">
          Join the community to see who is coming, and to say that you are.
        </p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          <Link href="/signup" className="btn-primary">Sign up</Link>
          <Link href="/events" className="btn-quiet">Back to events</Link>
        </div>
      </section>
    );
  }

  const { data: going } = await supabase
    .from('event_interests')
    .select('id, created_at, profile:profiles(id, full_name, avatar_url, title, facebook_url, instagram_url)')
    .eq('event_id', event.id)
    .order('created_at', { ascending: true });

  const { data: contacts } = await supabase.rpc('visible_contacts');
  const contactById = new Map((contacts || []).map((c) => [c.id, c.contact_number]));
  const rows = going || [];

  return (
    <div className="stack-l">
      <PageHeader
        eyebrow={eventDate(event.starts_at)}
        title={event.title}
        lead={
          rows.length
            ? `${rows.length} ${rows.length === 1 ? 'person has' : 'people have'} said they are coming${event.location ? ` · ${event.location}` : ''}.`
            : 'Nobody has said they are coming yet.'
        }
        action={<Link href="/events" className="btn-outline">Back to events</Link>}
      />

      {rows.length ? (
        <ul className="shell-narrow grid gap-3 sm:grid-cols-2">
          {rows.map((row, i) => (
            <Reveal key={row.id} delay={Math.min(i, 6) * 50} as="li">
              <div className="card flex items-center gap-3">
                <Avatar url={row.profile?.avatar_url} name={row.profile?.full_name} size={40} />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{row.profile?.full_name}</p>
                  {row.profile?.title && (
                    <p className="truncate text-xs text-ink/50">{row.profile.title}</p>
                  )}
                  <SocialLinks
                    profile={{ ...row.profile, contact_number: contactById.get(row.profile?.id) }}
                    className="mt-1"
                    size={16}
                  />
                </div>
              </div>
            </Reveal>
          ))}
        </ul>
      ) : (
        <div className="card card-static py-12 text-center text-ink/60">
          <p className="font-medium text-ink/75">Be the first</p>
          <p className="mx-auto mt-1 max-w-xs text-sm">
            Say you are coming and others will see they will not be walking in alone.
          </p>
          <Link href="/events" className="btn-primary mt-6">Back to events</Link>
        </div>
      )}
    </div>
  );
}
