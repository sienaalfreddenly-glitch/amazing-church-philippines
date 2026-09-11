-- Tests for per-reader daily assignment, visitor mode, and reminder spending.
--
-- Run with:
--   docker exec -i supabase_db_amazing-church psql -U postgres -d postgres \
--     < scripts/daily-per-reader-tests.sql
--
-- Wrapped in a transaction that is rolled back, so it leaves no trace.

begin;

create temporary table results (name text, passed boolean, detail text) on commit drop;

create or replace function pg_temp.check_that(p_name text, p_passed boolean, p_detail text default '')
returns void language sql as $$
  insert into results values (p_name, p_passed, p_detail);
$$;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
values
 ('e1111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pr1@test.invalid','x',now(),'{"full_name":"Reader One"}'::jsonb,now(),now()),
 ('e2222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pr2@test.invalid','x',now(),'{"full_name":"Reader Two"}'::jsonb,now(),now());

update profiles set account_status = 'approved' where email like 'pr_@test.invalid';

-- ---------------------------------------------------------------------------
do $$
declare
  m1 record; m1again record; m2 record;
  v1 record; v2 record;
  visitor_a uuid := gen_random_uuid();
  visitor_b uuid := gen_random_uuid();
  today date := current_date;
begin
  select * into m1 from claim_daily_for('e1111111-1111-1111-1111-111111111111', null, today);
  select * into m2 from claim_daily_for('e2222222-2222-2222-2222-222222222222', null, today);

  perform pg_temp.check_that('a member receives an assignment', m1.assignment_id is not null);

  -- Refreshing returns the identical row.
  select * into m1again from claim_daily_for('e1111111-1111-1111-1111-111111111111', null, today);
  perform pg_temp.check_that(
    'refreshing returns the same assignment',
    m1again.assignment_id = m1.assignment_id and m1again.verse_ref = m1.verse_ref);

  perform pg_temp.check_that(
    'two members each get their own draw',
    m1.assignment_id <> m2.assignment_id);

  -- Visitors.
  select * into v1 from claim_daily_for(null, visitor_a, today);
  select * into v2 from claim_daily_for(null, visitor_b, today);

  perform pg_temp.check_that('a visitor receives an assignment', v1.assignment_id is not null);

  perform pg_temp.check_that(
    'a visitor only ever gets a welcoming verse',
    exists (
      select 1
      from daily_assignments a
      join verse_topics vt on vt.verse_id = a.verse_id
      join verse_topic_kinds k on k.slug = vt.topic
      where a.id = v1.assignment_id and k.visitor_safe
    ), v1.verse_ref);

  perform pg_temp.check_that(
    'two visitors each get their own draw',
    v1.assignment_id <> v2.assignment_id);

  perform pg_temp.check_that(
    'a visitor refresh returns the same assignment',
    (select assignment_id from claim_daily_for(null, visitor_a, today)) = v1.assignment_id);
end $$;

-- ---------------------------------------------------------------------------
-- The same verse may be held by two people on the same day. This is the
-- constraint that was deliberately removed, so it is worth proving gone.
do $$
declare
  v_id uuid; r_a uuid; r_b uuid; ok boolean := false;
begin
  select id into v_id from daily_verses where devotional order by random() limit 1;

  select generate_reminder_for(v_id) into r_a;
  select generate_reminder_for(v_id) into r_b;

  if r_a is null or r_b is null then
    perform pg_temp.check_that('the same verse may go to two readers on one day', false,
      'could not generate two reminders for one verse');
  else
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('e1111111-1111-1111-1111-111111111111', v_id, r_a, date '2096-01-01', 'test');
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('e2222222-2222-2222-2222-222222222222', v_id, r_b, date '2096-01-01', 'test');
    ok := true;
    perform pg_temp.check_that('the same verse may go to two readers on one day', ok);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Constraints that must hold whatever the application does.
do $$
declare
  spent uuid; v_other uuid; blocked boolean;
begin
  select reminder_id into spent from daily_assignments limit 1;
  select id into v_other from daily_verses where devotional order by random() limit 1;

  blocked := false;
  begin
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('e2222222-2222-2222-2222-222222222222', v_other, spent, date '2096-02-02', 'test');
  exception when unique_violation then blocked := true;
  end;
  perform pg_temp.check_that('a reminder can never be spent twice', blocked);

  blocked := false;
  begin
    insert into daily_assignments (user_id, visitor_id, verse_id, reminder_id, assigned_on, theme)
    values ('e1111111-1111-1111-1111-111111111111', gen_random_uuid(), v_other,
            generate_reminder_for(v_other), date '2096-03-03', 'test');
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('an assignment cannot have both a user and a visitor', blocked);

  blocked := false;
  begin
    insert into daily_assignments (verse_id, reminder_id, assigned_on, theme)
    values (v_other, generate_reminder_for(v_other), date '2096-04-04', 'test');
  exception when check_violation then blocked := true;
  end;
  perform pg_temp.check_that('an assignment must have one identity', blocked);

  -- One per member per day.
  blocked := false;
  begin
    insert into daily_assignments (user_id, verse_id, reminder_id, assigned_on, theme)
    values ('e1111111-1111-1111-1111-111111111111', v_other,
            generate_reminder_for(v_other), current_date, 'test');
  exception when unique_violation then blocked := true;
  end;
  perform pg_temp.check_that('one assignment per member per day', blocked);
end $$;

-- ---------------------------------------------------------------------------
-- Near-duplicate protection, now scoped to the verse.
do $$
declare
  v_id uuid; base text; blocked boolean := false;
begin
  select verse_id, reminder into v_id, base from daily_reminders limit 1;

  begin
    insert into daily_reminders (verse_id, reminder, theme, focus_tag)
    values (v_id, replace(base, 'you', 'You'), 'test', 'test');
  exception when unique_violation then blocked := true;
  end;

  perform pg_temp.check_that('a near-duplicate reminder is rejected within a verse', blocked);
end $$;

-- ---------------------------------------------------------------------------
select case when passed then 'PASS' else 'FAIL' end as result, name, detail
from results order by passed, name;

select count(*) filter (where passed) || ' passed, '
    || count(*) filter (where not passed) || ' failed' as summary
from results;

rollback;
