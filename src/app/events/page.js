import { createClient, getSessionAndProfile } from '@/lib/supabase-server';
import { isStaff } from '@/lib/roles';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function Events() {
  const { profile } = await getSessionAndProfile();
  const supabase = createClient();
  const { data: events } = await supabase
    .from('events').select('*')
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl">Events</h1>
        {isStaff(profile?.role) && <Link href="/admin/events" className="btn-primary">Manage events</Link>}
      </div>
      <div className="grid md:grid-cols-2 gap-4">
        {events?.length ? events.map(e => (
          <div key={e.id} className="card">
            <p className="text-xs uppercase text-brand tracking-wide">
              {new Date(e.starts_at).toLocaleString()}
            </p>
            <h3 className="text-xl mt-1">{e.title}</h3>
            {e.location && <p className="text-sm text-ink/60">{e.location}</p>}
            {e.description && <p className="mt-2 text-ink/80">{e.description}</p>}
          </div>
        )) : <p className="text-ink/60">No events posted yet.</p>}
      </div>
    </div>
  );
}
