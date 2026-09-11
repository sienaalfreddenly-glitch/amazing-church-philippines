-- Machine-written reminders, held for review.
--
-- Generated text is not shown to anybody until a leader approves it. This is
-- commentary on Scripture published under the church's name, so there is a
-- person between the model and the congregation. The hand-written library needs
-- no such gate because a person already wrote it.
--
-- Nothing here depends on a key being present. With no key configured the
-- generator simply never runs, the library keeps serving, and the site behaves
-- exactly as it does today.

-- 'pending' joins the existing states. Only 'active' is ever drawn.
alter table public.daily_reminders drop constraint if exists daily_reminders_status_check;
alter table public.daily_reminders
  add constraint daily_reminders_status_check
  check (status in ('active', 'pending', 'rejected', 'retired'));

alter table public.daily_reminders
  add column if not exists source       text not null default 'library'
    check (source in ('library', 'generated')),
  add column if not exists reviewed_by  uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at  timestamptz,
  add column if not exists model        text;

comment on column public.daily_reminders.source is
  'library: written by a person. generated: written by a model and reviewed before use.';

create index if not exists daily_reminders_pending_idx
  on public.daily_reminders (created_at) where status = 'pending';

-- Staff read the queue and decide. Members never see a pending reminder,
-- because the claim function only ever selects status = 'active'.
alter table public.daily_reminders enable row level security;

drop policy if exists "staff review reminders" on public.daily_reminders;
create policy "staff review reminders"
  on public.daily_reminders for select
  using (is_staff());

drop policy if exists "staff decide reminders" on public.daily_reminders;
create policy "staff decide reminders"
  on public.daily_reminders for update
  using (is_staff()) with check (is_staff());

grant select, update on public.daily_reminders to authenticated;

-- How much unreviewed work is waiting, and how much approved content is left.
create or replace function public.reminder_queue_stats()
returns table (pending bigint, approved bigint, rejected bigint, verses_covered bigint)
language sql
security definer
set search_path = public
stable
as $$
  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'active'),
    count(*) filter (where status = 'rejected'),
    count(distinct verse_id) filter (where status = 'active')
  from public.daily_reminders;
$$;

revoke all on function public.reminder_queue_stats() from public;
grant execute on function public.reminder_queue_stats() to authenticated;
