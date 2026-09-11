-- Separate the verse from its reminder.
--
-- The first version stored a verse and a reminder together as one pool row,
-- which meant a verse could only ever carry one reminder. When the same verse
-- came round again, for a different person or on a later day, it arrived with
-- exactly the same words attached. A verse should be able to speak to several
-- situations, so reminders now belong to a verse and a verse has many.
--
-- WHAT IS GUARANTEED NOW
--
--   A reminder is used once, ever.        unique index on (reminder_id)
--   No two people share a verse in a day. unique index on (assigned_on, verse_id)
--   One assignment per person per day.    unique index on (user_id, assigned_on)
--
-- The first of those is what this migration is for: because a reminder can
-- never be reused, a repeated verse necessarily arrives with different words.

create table if not exists public.daily_verses (
  id         uuid primary key default gen_random_uuid(),
  reference  text not null,
  verse_text text not null,
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  reference_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reference), '[^a-z0-9: ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  constraint verse_reference_is_real check (public.is_valid_bible_reference(reference)),
  constraint verse_no_em_dash check (verse_text !~ '[—–]')
);

create unique index if not exists daily_verses_reference_uniq on public.daily_verses (reference_norm);

create table if not exists public.daily_reminders (
  id         uuid primary key default gen_random_uuid(),
  verse_id   uuid not null references public.daily_verses(id) on delete cascade,
  reminder   text not null,
  theme      text not null,
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  reminder_norm text generated always as (
    trim(regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'))
  ) stored,

  constraint reminder_length check (
    array_length(regexp_split_to_array(trim(reminder), '\s+'), 1) between 50 and 90
  ),
  constraint reminder_no_em_dash check (reminder !~ '[—–]'),
  constraint reminder_no_emoji check (reminder ~ '^[\x00-\x7F''’"“”]*$'),
  constraint reminder_no_hashtag check (reminder !~ '#')
);

create unique index if not exists daily_reminders_norm_uniq on public.daily_reminders (reminder_norm);
create index if not exists daily_reminders_verse_idx on public.daily_reminders (verse_id) where status = 'active';
create index if not exists daily_reminders_trgm on public.daily_reminders using gin (reminder_norm gin_trgm_ops);

-- Near duplicates refused on write, comparing against new.reminder directly
-- because a stored generated column is not populated until after this runs.
create or replace function public.reject_similar_reminder()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  candidate_norm text;
  clash record;
begin
  candidate_norm := trim(regexp_replace(
    regexp_replace(lower(new.reminder), '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));

  select id, similarity(reminder_norm, candidate_norm) as score
    into clash
  from public.daily_reminders
  where id <> new.id
    and similarity(reminder_norm, candidate_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception 'reminder is too similar (%) to existing reminder %',
      round(clash.score::numeric, 3), clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists daily_reminders_similarity on public.daily_reminders;
create trigger daily_reminders_similarity
  before insert or update of reminder on public.daily_reminders
  for each row execute function public.reject_similar_reminder();

-- ---------------------------------------------------------------------------
-- Carry the existing pool across, then rebuild the assignments table around
-- the two new keys.
-- ---------------------------------------------------------------------------

insert into public.daily_verses (reference, verse_text)
select distinct on (verse_ref) verse_ref, verse_text
from public.daily_content
on conflict do nothing;

insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, c.reminder, c.theme
from public.daily_content c
join public.daily_verses v on v.reference = c.verse_ref
on conflict do nothing;

drop table if exists public.daily_assignments cascade;

create table public.daily_assignments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  verse_id    uuid not null references public.daily_verses(id)    on delete restrict,
  reminder_id uuid not null references public.daily_reminders(id) on delete restrict,
  assigned_on date not null,
  theme       text not null,
  status      text not null default 'active' check (status in ('active', 'superseded')),
  created_at  timestamptz not null default now(),

  constraint one_per_user_per_day unique (user_id, assigned_on),
  constraint one_verse_per_day    unique (assigned_on, verse_id),
  -- A reminder is spent once and never comes back, which is what makes a
  -- repeated verse arrive with new words.
  constraint reminder_used_once   unique (reminder_id)
);

create index daily_assignments_user_idx  on public.daily_assignments (user_id, assigned_on desc);
create index daily_assignments_verse_idx on public.daily_assignments (verse_id, assigned_on desc);

alter table public.daily_verses     enable row level security;
alter table public.daily_reminders  enable row level security;
alter table public.daily_assignments enable row level security;

drop policy if exists "assignments are private" on public.daily_assignments;
create policy "assignments are private"
  on public.daily_assignments for select using (user_id = auth.uid());

grant select on public.daily_assignments to authenticated;

drop table if exists public.daily_content cascade;
-- Claim a verse and, separately, a reminder belonging to that verse.
--
-- The reminder is chosen from the ones attached to the chosen verse that have
-- never been used by anybody. Because reminder_used_once makes a reminder
-- unrepeatable, a verse seen a second time necessarily arrives with different
-- words. A verse with no unused reminders left is skipped entirely rather than
-- being shown with a repeat.
create or replace function public.claim_daily_content(p_user uuid, p_day date)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  reminder      text,
  theme         text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  r_id     uuid;
  r_theme  text;
  attempts int := 0;
  made     uuid;
begin
  select a.id into made
  from public.daily_assignments a
  where a.user_id = p_user and a.assigned_on = p_day;

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 40;

      -- A verse still free today that has at least one unused reminder.
      select v.id into v_id
      from public.daily_verses v
      where v.status = 'active'
        and not exists (
          select 1 from public.daily_assignments a
          where a.assigned_on = p_day and a.verse_id = v.id
        )
        and exists (
          select 1 from public.daily_reminders r
          where r.verse_id = v.id and r.status = 'active'
            and not exists (select 1 from public.daily_assignments a2 where a2.reminder_id = r.id)
        )
      order by
        -- Prefer a verse this person has not had before.
        (exists (select 1 from public.daily_assignments a
                 where a.user_id = p_user and a.verse_id = v.id)),
        -- Then whatever has gone longest unused by anyone.
        coalesce((select max(a.assigned_on) from public.daily_assignments a
                  where a.verse_id = v.id), date '1970-01-01'),
        md5(v.id::text || p_day::text)
      limit 1;

      exit when v_id is null;

      -- An unused reminder for that verse. Fresh words every time the verse
      -- appears, which is the whole point of the split.
      select r.id, r.theme into r_id, r_theme
      from public.daily_reminders r
      where r.verse_id = v_id and r.status = 'active'
        and not exists (select 1 from public.daily_assignments a where a.reminder_id = r.id)
      order by md5(r.id::text || p_user::text || p_day::text)
      limit 1;

      continue when r_id is null;

      insert into public.daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
      values (p_user, v_id, r_id, p_day, r_theme)
      on conflict do nothing
      returning id into made;

      exit when made is not null;
      -- Lost a race on the verse or the reminder. Go round again.
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, v.reference, v.verse_text, r.reminder, a.theme, a.assigned_on, a.created_at
  from public.daily_assignments a
  join public.daily_verses v    on v.id = a.verse_id
  join public.daily_reminders r on r.id = a.reminder_id
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_content(uuid, date) from public;
grant execute on function public.claim_daily_content(uuid, date) to authenticated;
insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, r.reminder, r.theme from public.daily_verses v
join (values
('Zephaniah 3:17','Think about how you talk to yourself when you get something wrong. Most of us are far harsher than we would ever be with a friend. God is not adding his voice to that pile. He looks at you the way a parent looks at a child asleep in the back of the car. Tired, imperfect, and completely theirs. Let that be the last thing you hear tonight.','God''s love'),
('Isaiah 41:10','Fear tends to arrive loudest at about two in the morning, when nothing can actually be done. If that is where you are, you are not weak for lying awake. Say the worry out loud, name it properly, and then hand it over until morning. God is awake anyway. You are allowed to stop guarding the situation for a few hours and sleep.','Courage when facing fear'),
('Lamentations 3:22-23','Some seasons feel like one long repeat of the same mistake. You apologise, you mean it, and a fortnight later you are back. God is not keeping a tally that runs out. His patience is not a limited supply you have been drawing down since childhood. Get up again today. Not with shame driving you, but because there is genuinely more mercy waiting.','Forgiveness and grace'),
('Matthew 11:28','There is a difference between being busy and being weighed down. Busy passes. Weighed down follows you into the evening and sits on your chest. If that is you, work out what you are actually carrying, because it is rarely only the diary. Bring the real thing to God, and let somebody help you with a piece of it this week.','Rest when feeling tired'),
('Psalm 27:14','The hardest part of waiting is not knowing whether anything is happening. You want a sign that the situation is moving. Often there is none, and you have to decide to keep showing up anyway. That decision is not naive. It is courage of a quiet kind, and God sees it even when nobody else notices you are still standing there.','Hope while waiting'),
('Philippians 4:6-7','Money worries have a particular way of taking over. They follow you into the shower and the commute and the middle of a conversation. If the numbers are not working this month, God is not disappointed in you for it. Tell him exactly what the shortfall is. Then tell one person you trust, because carrying a financial fear alone makes it heavier than it is.','Peace during stressful moments'),
('Proverbs 3:5-6','You might be second-guessing a choice you already made. Turning it over does not change it, and replaying it only wears you out. If you asked honestly and chose with what you knew at the time, you did the thing you were meant to do. God can work with a decision that turns out imperfectly. He has done it with every person who ever followed him.','Trusting God''s direction'),
('Joshua 1:9','Sometimes the brave thing is very small. Sending the message. Booking the appointment. Walking into a room where you do not know anyone. Nobody will applaud any of it, and it will still cost you something. God is with you in the small brave things just as much as the large ones, and today probably only asks for one of the small ones.','Strength during difficult times'),
('Psalm 34:18','If somebody you love is struggling and you cannot fix it, that helplessness is its own ache. You want to do something useful and there is nothing to do. Sitting with them is not nothing. It is most of what love looks like when there is no solution. God does the same for you, and he is close to them too.','Healing and comfort'),
('Galatians 6:9','There is a kind of tiredness that comes from caring about something nobody else seems to care about. You keep turning up and it keeps looking the same. Rest properly, then decide again. Not because giving up would be wrong, but because the thing you are doing is worth more than it currently looks, and you may be closer than you think.','Perseverance after disappointment'),
('James 1:5','Wisdom often arrives as a slow narrowing rather than a bright idea. You rule something out, then something else, and eventually one option is left that you can live with. That is God guiding you just as much as any dramatic moment would be. Give yourself permission to take the boring, sensible route. It is usually the one that holds.','Wisdom and guidance'),
('1 Thessalonians 5:16-18','Try noticing one thing today that you would normally walk straight past. The way the light came through the window. Someone letting you go first. A meal you did not have to worry about paying for. None of that fixes what is hard, and it is not meant to. It simply reminds you that good things are still arriving, unearned, all the time.','Gratitude')
) as r(ref, reminder, theme) on v.reference = r.ref;
insert into public.daily_reminders (verse_id, reminder, theme)
select v.id, r.reminder, r.theme from public.daily_verses v
join (values
('Romans 8:28','You may be looking back at a stretch of your life that felt pointless at the time. The job that went nowhere, the years that seemed wasted. God does not discard those. People who have been through something difficult tend to be the ones others can actually talk to. What felt like a detour often turns out to be the reason someone trusts you later.','Purpose and faith'),
('Psalm 46:10','Your phone is very good at making you feel responsible for things happening a long way away. Some of that concern is right and most of it is simply noise you cannot act on. Put it down for an hour this evening. The world will keep turning without your attention on it, which is a relief rather than an insult.','Peace during stressful moments'),
('Isaiah 40:31','Recovery from anything, illness or burnout or grief, is rarely a straight line. You have a good week and then a bad afternoon and assume you are back where you started. You are not. Progress that dips is still progress. Judge it over months rather than days, and be as patient with yourself as you would be with anyone else.','Strength during difficult times'),
('Ephesians 4:32','Being kind is easiest with people who are easy. The test is the relative who always says the wrong thing, or the colleague who takes credit. You do not have to feel warm towards them to treat them decently. Start with not repeating the story about them, and see how much lighter the next conversation feels.','Forgiveness and grace'),
('1 Peter 5:7','Parents carry a specific worry that never fully switches off, even when everyone is safely asleep. If that is you, you are not failing because you cannot stop thinking about it. You cannot control every outcome, and you were never meant to. Hand the ones you love back to God tonight. He is more invested in them than you are.','Peace during stressful moments'),
('Colossians 3:23','If you are between jobs, or in one that is well below what you can do, that is a wearing place to be. Your worth is not set by a job title and it never was. Do today''s work properly, keep looking, and let somebody help. God is not measuring your value by your payslip, and you should not either.','Purpose and faith'),
('Psalm 73:26','Chronic pain or a long illness wears down faith in a way that sudden crisis does not. There is no dramatic moment, only the daily grind of it. If you have stopped being able to pray in sentences, that is fine. God is not waiting for eloquence. Being present and still breathing is a form of holding on.','Healing and comfort'),
('Romans 12:12','There is a conversation you have been rehearsing for weeks. It may go badly. It may also go far better than the version in your head, because the version in your head assumes the worst. Wait until you are calm rather than until you feel ready, because ready may not come. Then say the true thing kindly.','Patience'),
('John 14:27','A house can be quiet and still not be peaceful. If things are tense at home, you probably feel it in your shoulders before you notice it in your thoughts. Peace does not mean pretending everything is fine. It might start with one honest sentence, said gently, at a moment when nobody is already angry.','Peace during stressful moments'),
('Deuteronomy 31:8','Moving somewhere new strips away all the small things that made you feel competent. You do not know the roads, the shops, or anyone''s name. That disorientation is normal and it does pass. God is not only in the place you left. He is already in the new one, in people you have not met yet.','Courage when facing fear'),
('Psalm 121:1-2','When you are the one everybody leans on, it is easy to forget that you are allowed to need help too. Being capable is not the same as being fine. Ask somebody for something this week, even something small. Letting yourself be helped is part of what keeps you able to help anyone else.','Trusting God''s direction'),
('2 Corinthians 12:9','There is something about yourself you would change if you could. A temper, an anxiety, a limitation you did not choose. God is not waiting for you to fix it before he can use you. Some of the most genuine people you know are genuine precisely because they stopped pretending. You are allowed to be a work in progress.','God''s love')
) as r(ref, reminder, theme) on v.reference = r.ref;
