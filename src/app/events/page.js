import Link from 'next/link';
import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff, isApproved } from '@/lib/roles';
import PageHeader from '@/components/PageHeader';
import Reveal from '@/components/Reveal';
import Spotlight from '@/components/Spotlight';
import EventInterestButton from '@/components/EventInterestButton';
import { IconCalendar, IconMapPin } from '@/components/Icons';
import { eventDate, eventDateParts } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function Events() {
  const { user, profile } = await getSessionAndProfile();
  const canRespond = isApproved(profile);
  const supabase = createClient();

  const { data: events } = await supabase
    .from('events').select('*')
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true });

  // One read for every event's headcount, rather than a query per card.
  const { data: interests } = canRespond
    ? await supabase.from('event_interests').select('event_id, profile_id')
    : { data: [] };

  const countByEvent = new Map();
  const mine = new Set();
  for (const row of interests || []) {
    countByEvent.set(row.event_id, (countByEvent.get(row.event_id) || 0) + 1);
    if (row.profile_id === user?.id) mine.add(row.event_id);
  }

  const items = events || [];

  return (
    <div className="stack-l">
      <PageHeader
        eyebrow="What is on"
        title="Events"
        lead="Services, outreach, and everything else worth turning up to. Tell us you are coming and we will look out for you."
        action={isStaff(profile?.role) && (
          <Link href="/admin/events" className="btn-outline">Manage events</Link>
        )}
      />

      {items.length ? (
        <div className="grid gap-5 md:grid-cols-2">
          {items.map((e, i) => {
            const { day, month } = eventDateParts(e.starts_at);
            const count = countByEvent.get(e.id) || 0;

            return (
              <Reveal key={e.id} delay={Math.min(i, 4) * 80}>
                <Spotlight className="h-full rounded-2xl">
                  <article className="card card-body h-full">
                    <div className="flex items-start gap-4">
                      {/* A date block rather than a line of text, so a card is
                          scannable at a glance down a column. */}
                      <div className="nums flex w-14 shrink-0 flex-col items-center justify-center rounded-xl bg-brand py-2.5 text-white shadow-gilt">
                        <span className="text-xl font-semibold leading-none">{day}</span>
                        <span className="mt-1 text-[10px] font-semibold uppercase tracking-wider text-gilt-light">
                          {month}
                        </span>
                      </div>

                      <div className="min-w-0">
                        <h2 className="text-xl leading-snug">{e.title}</h2>
                        <p className="nums mt-1 inline-flex items-center gap-1.5 text-xs font-medium text-ink/55">
                          <IconCalendar size={13} /> {eventDate(e.starts_at)}
                        </p>
                        {e.location && (
                          <p className="mt-1 inline-flex items-center gap-1.5 text-sm text-ink/60">
                            <IconMapPin size={14} /> {e.location}
                          </p>
                        )}
                      </div>
                    </div>

                    {e.description && (
                      <p className="mt-4 text-ink/75">{e.description}</p>
                    )}

                    <EventInterestButton
                      eventId={e.id}
                      canRespond={canRespond}
                      initiallyGoing={mine.has(e.id)}
                      count={count}
                    />

                    {canRespond && count > 0 && (
                      <p className="mt-2 text-sm">
                        <Link
                          href={`/events/${e.id}/going`}
                          className="text-brand underline-offset-4 hover:underline"
                        >
                          See who is coming
                        </Link>
                      </p>
                    )}
                  </article>
                </Spotlight>
              </Reveal>
            );
          })}
        </div>
      ) : (
        <div className="card card-static py-14 text-center">
          <div className="inline-block animate-floaty text-brand"><IconCalendar size={40} /></div>
          <p className="mt-4 font-medium text-ink/75">Nothing on the calendar yet</p>
          <p className="mx-auto mt-1 max-w-xs text-sm text-ink/60">
            Sunday service still runs every week. Watch it on the livestream page.
          </p>
          <Link href="/live" className="btn-outline mt-6">Watch live</Link>
        </div>
      )}
    </div>
  );
}
