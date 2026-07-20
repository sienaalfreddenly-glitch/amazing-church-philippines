import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { redirect } from 'next/navigation';
import { isStaff } from '@/lib/roles';
import ConfirmDeleteEventButton from '@/components/ConfirmDeleteEventButton';
import { IconMapPin } from '@/components/Icons';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

const dtLocal = (v) => v ? new Date(v).toISOString().slice(0, 16) : '';

export default async function ManageEvents() {
  const { profile } = await getSessionAndProfile();
  if (!profile || !isStaff(profile.role)) redirect('/');

  const supabase = createClient();
  const { data: events } = await supabase.from('events').select('*').order('starts_at', { ascending: false });
  const list = events || [];
  const now = Date.now();
  const upcoming = list.filter(e => new Date(e.starts_at).getTime() >= now);
  const past = list.filter(e => new Date(e.starts_at).getTime() < now);

  return (
    <div className="space-y-8">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-3xl">Events</h1>
          <p className="text-ink/60 text-sm">Create and manage church events.</p>
        </div>
        <Link href="/events" className="btn-outline">View public page →</Link>
      </div>

      <details className="card" open>
        <summary className="cursor-pointer font-semibold text-brand">+ Create a new event</summary>
        <EventForm />
      </details>

      <section>
        <h2 className="text-xl mb-3">Upcoming ({upcoming.length})</h2>
        <div className="space-y-3">
          {upcoming.length === 0 && <p className="text-sm text-ink/60">No upcoming events.</p>}
          {upcoming.map(e => <EventCard key={e.id} event={e} />)}
        </div>
      </section>

      {past.length > 0 && (
        <section>
          <h2 className="text-xl mb-3 text-ink/60">Past ({past.length})</h2>
          <div className="space-y-3 opacity-80">
            {past.slice(0, 20).map(e => <EventCard key={e.id} event={e} />)}
          </div>
        </section>
      )}
    </div>
  );
}

function EventCard({ event }) {
  return (
    <details className="card">
      <summary className="cursor-pointer flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs uppercase tracking-wider text-brand font-semibold">
            {new Date(event.starts_at).toLocaleString()}
          </p>
          <p className="font-semibold text-lg">{event.title}</p>
          {event.location && (
            <p className="text-xs text-ink/60 inline-flex items-center gap-1 mt-1">
              <IconMapPin size={12} /> {event.location}
            </p>
          )}
        </div>
        <span className="text-xs text-ink/50">click to edit</span>
      </summary>
      <div className="mt-4 border-t border-silver-light pt-4">
        <EventForm event={event} />
        <div className="mt-3 flex justify-end">
          <ConfirmDeleteEventButton id={event.id} />
        </div>
      </div>
    </details>
  );
}

function EventForm({ event }) {
  const e = event || {};
  return (
    <form action="/api/admin/events/upsert" method="post" className="mt-3 space-y-3">
      {e.id && <input type="hidden" name="id" value={e.id} />}
      <div>
        <label className="label">Title</label>
        <input className="input" name="title" required defaultValue={e.title || ''} placeholder="Sunday Service" />
      </div>
      <div>
        <label className="label">Description (optional)</label>
        <textarea className="input min-h-[80px]" name="description" defaultValue={e.description || ''} />
      </div>
      <div className="grid sm:grid-cols-2 gap-3">
        <div>
          <label className="label">Starts</label>
          <input className="input" name="starts_at" type="datetime-local" required defaultValue={dtLocal(e.starts_at)} />
        </div>
        <div>
          <label className="label">Ends (optional)</label>
          <input className="input" name="ends_at" type="datetime-local" defaultValue={dtLocal(e.ends_at)} />
        </div>
      </div>
      <div>
        <label className="label">Location</label>
        <input className="input" name="location" defaultValue={e.location || ''} placeholder="Church address, Zoom, etc." />
      </div>
      <div>
        <label className="label">Cover image URL (optional)</label>
        <input className="input" name="cover_url" defaultValue={e.cover_url || ''} placeholder="https://…" />
      </div>
      <div className="flex justify-end">
        <button className="btn-primary">{e.id ? 'Save changes' : 'Create event'}</button>
      </div>
    </form>
  );
}
