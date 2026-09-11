-- Which verses most need a reminder written for them.
--
-- Ordered by how few approved reminders they already hold, so coverage spreads
-- rather than deepening on verses that are already well served. A verse with
-- nothing approved is one the daily draw has to skip over, so those come first.
-- The random tiebreak stops the same verses being chosen on every run.

create or replace function public.verses_needing_reminders(p_limit int default 20)
returns table (id uuid, reference text, verse_text text, approved bigint)
language sql
security definer
set search_path = public
stable
as $$
  select v.id, v.reference, v.verse_text,
         count(r.id) filter (where r.status = 'active') as approved
  from public.daily_verses v
  left join public.daily_reminders r on r.verse_id = v.id
  where v.status = 'active' and v.devotional
  group by v.id, v.reference, v.verse_text
  order by approved asc, random()
  limit greatest(1, least(p_limit, 200));
$$;

revoke all on function public.verses_needing_reminders(int) from public;
grant execute on function public.verses_needing_reminders(int) to authenticated;
