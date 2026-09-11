-- Database-level tests for Daily Bible Verse.
--
-- These cover what unit tests cannot: the uniqueness and concurrency
-- guarantees, which are properties of the schema rather than of any code path.
--
-- Run with:
--   docker exec -i supabase_db_amazing-church psql -U postgres -d postgres \
--     < scripts/daily-db-tests.sql
--
-- Everything happens inside a transaction that is rolled back, so running this
-- against a live database leaves no trace.

begin;

create temporary table results (name text, passed boolean, detail text) on commit drop;

create or replace function pg_temp.check_that(p_name text, p_passed boolean, p_detail text default '')
returns void language sql as $$
  insert into results values (p_name, p_passed, p_detail);
$$;

-- Three test users.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
values
 ('d1111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','daily1@test.invalid','x',now(),'{"full_name":"Daily One"}'::jsonb,now(),now()),
 ('d2222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','daily2@test.invalid','x',now(),'{"full_name":"Daily Two"}'::jsonb,now(),now()),
 ('d3333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','daily3@test.invalid','x',now(),'{"full_name":"Daily Three"}'::jsonb,now(),now());

update profiles set account_status = 'approved'
where email in ('daily1@test.invalid','daily2@test.invalid','daily3@test.invalid');

-- ---------------------------------------------------------------------------
do $$
declare
  a1 record; a2 record; a3 record; again record;
  today date := current_date;
begin
  select * into a1 from claim_daily_content('d1111111-1111-1111-1111-111111111111', today);
  select * into a2 from claim_daily_content('d2222222-2222-2222-2222-222222222222', today);
  select * into a3 from claim_daily_content('d3333333-3333-3333-3333-333333333333', today);

  perform pg_temp.check_that('a new user receives an assignment', a1.assignment_id is not null);

  perform pg_temp.check_that(
    'each user receives a different verse',
    a1.verse_ref <> a2.verse_ref and a2.verse_ref <> a3.verse_ref and a1.verse_ref <> a3.verse_ref,
    format('%s / %s / %s', a1.verse_ref, a2.verse_ref, a3.verse_ref));

  perform pg_temp.check_that(
    'each user receives a different reminder',
    a1.reminder <> a2.reminder and a2.reminder <> a3.reminder and a1.reminder <> a3.reminder);

  -- Refreshing must return the identical assignment, not draw again.
  select * into again from claim_daily_content('d1111111-1111-1111-1111-111111111111', today);
  perform pg_temp.check_that(
    'refreshing returns the same assignment',
    again.assignment_id = a1.assignment_id and again.verse_ref = a1.verse_ref);

  perform pg_temp.check_that(
    'the assignment date is stored correctly',
    a1.assigned_on = today, a1.assigned_on::text);

  perform pg_temp.check_that(
    'a creation timestamp is recorded',
    a1.created_at is not null);

  perform pg_temp.check_that(
    'a theme is recorded',
    coalesce(a1.theme, '') <> '', a1.theme);
end $$;

-- ---------------------------------------------------------------------------
-- Two users cannot hold the same content on the same day, even if application
-- logic tries to force it.
do $$
declare
  taken uuid;
  taken_reminder uuid;
  failed boolean := false;
begin
  select verse_id, reminder_id into taken, taken_reminder from daily_assignments
  where assigned_on = current_date limit 1;

  begin
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('d3333333-3333-3333-3333-333333333333', taken, taken_reminder, current_date, 'God''s love');
  exception when unique_violation then
    failed := true;
  end;

  perform pg_temp.check_that('the database refuses a duplicate assignment', failed);
end $$;

-- ---------------------------------------------------------------------------
-- Content rules are enforced by the schema, not only by the seed script.
do $$
declare blocked boolean;
begin
  blocked := false;
  begin
    insert into daily_verses (reference, verse_text) values ('Hezekiah 3:16', 'Not a real book.');
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('a fabricated Bible reference is rejected', blocked);

  blocked := false;
  begin
    insert into daily_reminders (verse_id, reminder, theme)
    select id, 'far too short to be a reminder', 'God''s love' from daily_verses limit 1;
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('a reminder outside 50 to 90 words is rejected', blocked);

  blocked := false;
  begin
    insert into daily_reminders (verse_id, reminder, theme)
    select id, repeat('word ', 59) || 'and — a dash', 'God''s love' from daily_verses limit 1;
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('a reminder containing an em dash is rejected', blocked);

  blocked := false;
  begin
    insert into daily_reminders (verse_id, reminder, theme)
    select id, repeat('word ', 59) || 'and an emoji 🙏', 'God''s love' from daily_verses limit 1;
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('a reminder containing an emoji is rejected', blocked);

  -- A near-identical reminder must be refused, not merely an exact copy.
  blocked := false;
  begin
    insert into daily_reminders (verse_id, reminder, theme)
    select verse_id, replace(reminder, 'really', 'truly'), theme
    from daily_reminders where reminder like '%really noticed you%' limit 1;
  exception when unique_violation then blocked := true;
  end;
  perform pg_temp.check_that('a lightly reworded reminder is rejected as too similar', blocked);
end $$;

-- ---------------------------------------------------------------------------
-- The rule this model exists for: a verse that comes round again must arrive
-- with a different reminder, never the same words twice.
do $$
declare
  v_id      uuid;
  first_r   uuid;  first_text  text;
  second_r  uuid;  second_text text;
  blocked   boolean := false;
begin
  -- A verse that still has at least two unspent reminders, so the test is
  -- about the rule rather than about how much pool earlier blocks consumed.
  select r.verse_id into v_id
  from daily_reminders r
  where not exists (select 1 from daily_assignments a where a.reminder_id = r.id)
  group by r.verse_id having count(*) >= 2
  limit 1;

  if v_id is null then
    perform pg_temp.check_that('the same verse a second time carries a different reminder',
      false, 'no verse had two unspent reminders');
    return;
  end if;

  select dr.id, dr.reminder into first_r, first_text from daily_reminders dr
  where dr.verse_id = v_id
    and not exists (select 1 from daily_assignments a where a.reminder_id = dr.id)
  limit 1;

  insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
  values ('d1111111-1111-1111-1111-111111111111', v_id, first_r, date '2097-03-01', 'test');

  select dr.id, dr.reminder into second_r, second_text from daily_reminders dr
  where dr.verse_id = v_id
    and not exists (select 1 from daily_assignments a where a.reminder_id = dr.id)
  limit 1;

  insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
  values ('d2222222-2222-2222-2222-222222222222', v_id, second_r, date '2097-03-02', 'test');

  perform pg_temp.check_that(
    'the same verse a second time carries a different reminder',
    second_text is not null and second_text <> first_text);

  -- The database refuses to spend a reminder twice, whatever the caller does.
  begin
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('d3333333-3333-3333-3333-333333333333', v_id, first_r, date '2097-03-03', 'test');
  exception when unique_violation then blocked := true;
  end;

  perform pg_temp.check_that('a reminder can never be used twice', blocked);
end $$;

-- ---------------------------------------------------------------------------
-- Pool exhaustion returns nothing rather than a duplicate.
do $$
declare
  pool_size int;
  extra     record;
  spare     uuid;
begin
  select count(*) into pool_size from daily_verses where status = 'active';

  -- Fill every remaining slot for a distant date.
  for i in 1..pool_size loop
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
    values (gen_random_uuid(),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
            'fill' || i || '@test.invalid','x',now(),'{"full_name":"Filler"}'::jsonb,now(),now());
  end loop;

  update profiles set account_status = 'approved' where email like 'fill%@test.invalid';

  for spare in select id from profiles where email like 'fill%@test.invalid' loop
    perform claim_daily_content(spare, date '2099-01-01');
  end loop;

  -- One more person on a fully booked day.
  select * into extra from claim_daily_content('d1111111-1111-1111-1111-111111111111', date '2099-01-01');

  perform pg_temp.check_that(
    'an exhausted pool returns nothing rather than a duplicate',
    extra.assignment_id is null);

  perform pg_temp.check_that(
    'no two assignments share content on the exhausted day',
    (select count(*) from (
       select verse_id from daily_assignments
       where assigned_on = date '2099-01-01'
       group by verse_id having count(*) > 1
     ) dupes) = 0);
end $$;

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
select
  case when passed then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by passed, name;

select count(*) filter (where passed) || ' passed, '
    || count(*) filter (where not passed) || ' failed' as summary
from results;

rollback;
