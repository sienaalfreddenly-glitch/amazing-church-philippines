--
-- PostgreSQL database dump
--

-- Dumped from database version 15.6
-- Dumped by pg_dump version 15.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;
SET search_path = public, pg_catalog;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: approval_status; Type: TYPE; Schema: public; Owner: -
--

DO $$ BEGIN
CREATE TYPE public.approval_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);
EXCEPTION WHEN duplicate_object THEN null; END $$;


--
-- Name: enrollment_status; Type: TYPE; Schema: public; Owner: -
--

DO $$ BEGIN
CREATE TYPE public.enrollment_status AS ENUM (
    'enrolled',
    'completed',
    'dropped'
);
EXCEPTION WHEN duplicate_object THEN null; END $$;


--
-- Name: ministry_status; Type: TYPE; Schema: public; Owner: -
--

DO $$ BEGIN
CREATE TYPE public.ministry_status AS ENUM (
    'interested',
    'member',
    'declined'
);
EXCEPTION WHEN duplicate_object THEN null; END $$;


--
-- Name: notification_kind; Type: TYPE; Schema: public; Owner: -
--

DO $$ BEGIN
CREATE TYPE public.notification_kind AS ENUM (
    'enrolled',
    'lesson_verified',
    'reaction',
    'comment',
    'mention',
    'unassigned_member',
    'ministry_interest',
    'new_post',
    'new_discussion',
    'new_news',
    'new_event',
    'event_interest',
    'promoted'
);
EXCEPTION WHEN duplicate_object THEN null; END $$;


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

DO $$ BEGIN
CREATE TYPE public.user_role AS ENUM (
    'super_admin',
    'admin',
    'moderator',
    'user'
);
EXCEPTION WHEN duplicate_object THEN null; END $$;


--
-- Name: broadcast_to_members(uuid, public.notification_kind, text, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.broadcast_to_members(p_author uuid, p_kind public.notification_kind, p_entity_type text, p_entity_id uuid, p_metadata jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, p_author, p_kind, p_entity_type, p_entity_id, p_metadata
  from public.profiles p
  where p.account_status = 'approved'
    and p.is_hidden = false
    and p.id <> p_author
    and not exists (
      select 1 from public.notification_mutes m
      where m.muter_id = p.id and m.muted_id = p_author
    );
$$;


--
-- Name: can_manage_ministry(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.can_manage_ministry(m_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select is_staff()
      or exists (select 1 from public.ministries m
                 where m.id = m_id and m.leader_id = auth.uid());
$$;


--
-- Name: current_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public."current_role"() RETURNS public.user_role
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select role from public.profiles where id = auth.uid();
$$;


--
-- Name: ends_sentence(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.ends_sentence(t text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select trim(coalesce(t, '')) ~ '[.!?]["''’”]{0,2}$';
$_$;


--
-- Name: generate_reminder_for(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.generate_reminder_for(p_verse uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  t      record;
  new_id uuid;
  tries  int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 6;

    -- A template not yet used for this verse. Every verse can therefore carry
    -- every template exactly once, and never the same words twice.
    select rt.id, rt.text, rt.focus_tag into t
    from public.reminder_templates rt
    where rt.status = 'active'
      and rt.text is not null
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every template has been used for this verse. The caller moves to another
    -- verse rather than repeating one.
    if not found then
      return null;
    end if;

    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, t.text, t.focus_tag, t.focus_tag, t.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        -- Another request stored this template for this verse first, or the
        -- similarity guard caught it. Try a different template.
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
  end loop;

  return null;
end;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  chosen_leader uuid;
  leader_row    record;
  agreed        text;
begin
  begin
    chosen_leader := nullif(new.raw_user_meta_data->>'leader_id', '')::uuid;
  exception when others then
    chosen_leader := null;
  end;

  if chosen_leader is not null then
    if not exists (
      select 1 from public.profiles
      where id = chosen_leader and is_leader = true and account_status = 'approved'
    ) then
      chosen_leader := null;
    end if;
  end if;

  agreed := nullif(new.raw_user_meta_data->>'terms_accepted_version', '');

  insert into public.profiles (
    id, full_name, email, leader_id, terms_accepted_version, terms_accepted_at
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    chosen_leader,
    agreed,
    case when agreed is not null then now() end
  )
  on conflict (id) do nothing;

  if chosen_leader is null then
    for leader_row in
      select id from public.profiles
      where is_leader = true and account_status = 'approved'
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (
        leader_row.id,
        new.id,
        'unassigned_member',
        'profile',
        new.id,
        jsonb_build_object(
          'full_name', coalesce(new.raw_user_meta_data->>'full_name', new.email),
          'email', new.email
        )
      );
    end loop;
  end if;

  return new;
end;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select role in ('super_admin','admin')
       from public.profiles where id = auth.uid()),
    false);
$$;


--
-- Name: is_approved(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.is_approved() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select account_status = 'approved' from public.profiles where id = auth.uid()),
    false);
$$;


--
-- Name: is_staff(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select role in ('super_admin','admin','moderator')
       from public.profiles where id = auth.uid()),
    false);
$$;


--
-- Name: is_valid_bible_reference(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.is_valid_bible_reference(ref text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select ref ~ ('^(' || array_to_string(array[
    'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
    '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles','Ezra',
    'Nehemiah','Esther','Job','Psalms','Psalm','Proverbs','Ecclesiastes','Song of Solomon',
    'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
    'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
    'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
    'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
    '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
    '1 John','2 John','3 John','Jude','Revelation'
  ], '|') || ') [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$');
$_$;


--
-- Name: ministry_team(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.ministry_team(m_id uuid) RETURNS TABLE(profile_id uuid, full_name text, avatar_url text, role_in_team text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.id, p.full_name, p.avatar_url, mi.role_in_team
  from public.ministry_interests mi
  join public.profiles p on p.id = mi.profile_id
  where mi.ministry_id = m_id
    and mi.status = 'member'
    and p.account_status = 'approved'
  order by p.full_name;
$$;


--
-- Name: ministry_teams(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.ministry_teams() RETURNS TABLE(ministry_id uuid, profile_id uuid, full_name text, avatar_url text, role_in_team text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select mi.ministry_id, p.id, p.full_name, p.avatar_url, mi.role_in_team
  from public.ministry_interests mi
  join public.profiles p on p.id = mi.profile_id
  where mi.status = 'member'
    and p.account_status = 'approved'
    and p.is_hidden = false
  order by p.full_name;
$$;


--
-- Name: notify_comment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_comment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare tgt uuid; m uuid;
begin
  if new.entity_type = 'post' then
    select author_id into tgt from public.posts where id = new.entity_id;
  elsif new.entity_type = 'discussion' then
    select author_id into tgt from public.discussions where id = new.entity_id;
  end if;
  if tgt is not null and tgt <> new.author_id then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
    values (tgt, new.author_id, 'comment', new.entity_type, new.entity_id);
  end if;
  if new.mentions is not null then
    foreach m in array new.mentions loop
      if m is not null and m <> new.author_id then
        insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
        values (m, new.author_id, 'mention', 'comment', new.id);
      end if;
    end loop;
  end if;
  return new;
end $$;


--
-- Name: notify_enrollment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_enrollment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare course_code text;
begin
  select code into course_code from public.courses where id = new.course_id;
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  values (new.user_id, new.enrolled_by, 'enrolled', 'course', new.course_id,
          jsonb_build_object('course_code', course_code));
  return new;
end $$;


--
-- Name: notify_event_interest(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_event_interest() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  e         record;
  who       text;
  recipient record;
begin
  select title, created_by into e from public.events where id = new.event_id;
  select full_name into who from public.profiles where id = new.profile_id;

  for recipient in
    select id from public.profiles
    where is_leader = true and account_status = 'approved' and is_hidden = false
      and id <> new.profile_id
  loop
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (recipient.id, new.profile_id, 'event_interest', 'event', new.event_id,
            jsonb_build_object('full_name', who, 'title', e.title));
  end loop;

  return new;
end;
$$;


--
-- Name: notify_lesson_verified(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_lesson_verified() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare tgt uuid; lesson_title text; course_code text;
begin
  select user_id into tgt from public.enrollments where id = new.enrollment_id;
  select cl.title, c.code into lesson_title, course_code
    from public.course_lessons cl join public.courses c on c.id = cl.course_id
    where cl.id = new.lesson_id;
  if tgt is not null then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (tgt, new.verified_by, 'lesson_verified', 'lesson', new.lesson_id,
            jsonb_build_object('lesson_title', lesson_title, 'course_code', course_code));
  end if;
  return new;
end $$;


--
-- Name: notify_ministry_interest(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_ministry_interest() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  m           record;
  volunteer   text;
  recipient   record;
begin
  select name, leader_id into m from public.ministries where id = new.ministry_id;
  select full_name into volunteer from public.profiles where id = new.profile_id;

  if m.leader_id is not null then
    -- The ministry has someone responsible; only they need to hear about it.
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (m.leader_id, new.profile_id, 'ministry_interest', 'ministry', new.ministry_id,
            jsonb_build_object('full_name', volunteer, 'ministry', m.name));
  else
    -- Nobody owns this ministry yet, so tell every leader rather than let the
    -- volunteer go unanswered.
    for recipient in
      select id from public.profiles where is_leader = true and account_status = 'approved'
    loop
      insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
      values (recipient.id, new.profile_id, 'ministry_interest', 'ministry', new.ministry_id,
              jsonb_build_object('full_name', volunteer, 'ministry', m.name));
    end loop;
  end if;

  return new;
end;
$$;


--
-- Name: notify_new_discussion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_new_discussion() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare who text;
begin
  if new.status is distinct from 'approved' then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_discussion', 'discussion', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;


--
-- Name: notify_new_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_new_event() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare who text;
begin
  select full_name into who from public.profiles where id = new.created_by;
  perform broadcast_to_members(new.created_by, 'new_event', 'event', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;


--
-- Name: notify_new_news(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_new_news() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare who text;
begin
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_news', 'news', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;


--
-- Name: notify_new_post(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_new_post() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare who text;
begin
  -- Only announce what is actually visible. A post held for moderation should
  -- not ring every phone in the church.
  if new.status is distinct from 'approved' then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;


--
-- Name: notify_post_approved(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_post_approved() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare who text;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select full_name into who from public.profiles where id = new.author_id;
    perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
      jsonb_build_object('full_name', who, 'title', new.title));
  end if;
  return new;
end $$;


--
-- Name: notify_post_mentions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_post_mentions() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare m uuid; ent text;
begin
  ent := case when tg_table_name = 'posts' then 'post' else 'discussion' end;
  if new.mentions is not null then
    foreach m in array new.mentions loop
      if m is not null and m <> new.author_id then
        insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id)
        values (m, new.author_id, 'mention', ent, new.id);
      end if;
    end loop;
  end if;
  return new;
end $$;


--
-- Name: notify_reaction(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.notify_reaction() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare tgt uuid;
begin
  if new.entity_type = 'post' then
    select author_id into tgt from public.posts where id = new.entity_id;
  elsif new.entity_type = 'discussion' then
    select author_id into tgt from public.discussions where id = new.entity_id;
  elsif new.entity_type = 'comment' then
    select author_id into tgt from public.comments where id = new.entity_id;
  end if;
  if tgt is not null and tgt <> new.user_id then
    insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
    values (tgt, new.user_id, 'reaction', new.entity_type, new.entity_id,
            jsonb_build_object('emoji', new.emoji));
  end if;
  return new;
end $$;


--
-- Name: org_chart(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.org_chart() RETURNS TABLE(id uuid, full_name text, title text, avatar_url text, leader_id uuid, is_leader boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.id, p.full_name, p.title, p.avatar_url, p.leader_id, p.is_leader
  from public.profiles p
  where p.account_status = 'approved'
  order by p.is_leader desc, p.full_name;
$$;


--
-- Name: passage_for(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.passage_for(p_verse uuid) RETURNS TABLE(reference text, passage_text text, first_verse smallint, last_verse smallint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  anchor    record;
  first_v   smallint;
  last_v    smallint;
  max_v     smallint;
  guard     int := 0;
  prev_text text;
  last_text text;
  body      text;
  words     int;
begin
  select v.book, v.chapter, v.verse, v.verse_text
    into anchor
  from public.daily_verses v where v.id = p_verse;

  if not found then
    return;
  end if;

  select max(v.verse) into max_v
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter;

  first_v := anchor.verse;
  last_v  := anchor.verse;

  -- Backwards: if the verse before this one does not close a sentence, this
  -- verse is a continuation and the thought started earlier.
  loop
    guard := guard + 1;
    exit when guard > 6 or first_v <= 1;

    select v.verse_text into prev_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = first_v - 1;

    exit when prev_text is null or public.ends_sentence(prev_text);
    first_v := first_v - 1;
  end loop;

  -- Forwards: keep going until a verse closes a sentence, then keep going a
  -- little further so the passage has some shape rather than stopping at the
  -- first full stop.
  guard := 0;
  loop
    guard := guard + 1;
    exit when guard > 8 or last_v >= max_v;

    select v.verse_text into last_text
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter and v.verse = last_v;

    select coalesce(sum(array_length(regexp_split_to_array(trim(v.verse_text), '\s+'), 1)), 0)
      into words
    from public.daily_verses v
    where v.book = anchor.book and v.chapter = anchor.chapter
      and v.verse between first_v and last_v;

    -- Long enough and ending cleanly: stop here.
    exit when public.ends_sentence(last_text)
          and (last_v - first_v + 1) >= 3
          and words >= 45;

    -- Never run away with it, even mid-sentence.
    exit when words > 170 or (last_v - first_v + 1) >= 8;

    last_v := last_v + 1;
  end loop;

  select string_agg(v.verse_text, ' ' order by v.verse)
    into body
  from public.daily_verses v
  where v.book = anchor.book and v.chapter = anchor.chapter
    and v.verse between first_v and last_v;

  return query select
    anchor.book || ' ' || anchor.chapter || ':' || first_v
      || case when last_v > first_v then '-' || last_v else '' end,
    body,
    first_v,
    last_v;
end;
$$;


--
-- Name: profile_contact(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.profile_contact(target uuid) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  number     text;
  owner_lead uuid;
begin
  select p.contact_number, p.leader_id into number, owner_lead
  from public.profiles p where p.id = target;

  if number is null then
    return null;
  end if;

  -- Yourself: always.
  if target = auth.uid() then
    return number;
  end if;

  -- Staff: pastoral care and administration need to reach people.
  if is_staff() then
    return number;
  end if;

  -- The member's own leader: that is the point of having one.
  if owner_lead is not null and owner_lead = auth.uid() then
    return number;
  end if;

  -- Everyone else, including other members who were shown it before.
  return null;
end;
$$;


--
-- Name: FUNCTION profile_contact(target uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.profile_contact(target uuid) IS 'Returns a member phone number only to that member, their leader, or staff.';


--
-- Name: promote_member(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.promote_member(p_target uuid, p_to text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  actor_row  record;
  target_row record;
  new_title  text := p_to;
  message    text;
  leader_row record;
begin
  if new_title not in ('Leader', 'Pastor') then
    raise exception 'promote_member: target must be Leader or Pastor';
  end if;

  select p.id, p.role, p.title, p.full_name
    into actor_row
  from public.profiles p where p.id = auth.uid();
  if not found then
    raise exception 'not signed in';
  end if;

  select p.id, p.title, p.is_leader, p.full_name
    into target_row
  from public.profiles p where p.id = p_target;
  if not found then
    raise exception 'target not found';
  end if;

  -- What promotion is this? A Disciple becomes a Leader; a Leader becomes a
  -- Pastor. Anything else is rejected rather than silently normalised.
  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

  -- Who is allowed to promote? Super Admin bypasses. Otherwise use the
  -- actor's church title:
  --   Disciple -> Leader : Head Pastor, Pastor, Leader
  --   Leader   -> Pastor : Head Pastor, Pastor (never Leader)
  if actor_row.role <> 'super_admin' then
    if new_title = 'Leader' then
      if lower(coalesce(actor_row.title, '')) not in ('head pastor', 'pastor', 'leader') then
        raise exception 'not allowed to promote to Leader';
      end if;
    elsif new_title = 'Pastor' then
      if lower(coalesce(actor_row.title, '')) not in ('head pastor', 'pastor') then
        raise exception 'only Head Pastor or Pastor can promote to Pastor';
      end if;
    end if;
  end if;

  -- Apply the promotion.
  update public.profiles
     set is_leader = true,
         title     = new_title
   where id = target_row.id;

  -- The celebratory message. Warm, biblical in tone, deliberately not a
  -- quoted verse (chapter-and-verse quotations belong on the Daily Verse card,
  -- not stapled onto a personal announcement).
  if new_title = 'Leader' then
    message := format(
      'Rejoice with us. Today we set apart %s as a Leader in the household. ' ||
      'The Lord has been shaping this heart in quiet ways for a long time, and we bless ' ||
      'this next step of taking others under their care. May grace multiply, may wisdom ' ||
      'be given daily, and may the flock entrusted to them flourish.',
      target_row.full_name
    );
  else
    message := format(
      'Rejoice with us. Today we recognize %s as a Pastor in the household. ' ||
      'They have shepherded faithfully as a Leader, and we entrust to them a wider circle ' ||
      'of care. May the Chief Shepherd strengthen them, may their family be knit tightly ' ||
      'in love, and may every soul under their watch be brought closer to Christ.',
      target_row.full_name
    );
  end if;

  -- One feed post per promotion, authored by the actor's row for RLS reasons
  -- but flagged as a system post so the byline renders as the church.
  insert into public.posts (author_id, body, status, is_system)
  values (actor_row.id, message, 'approved', true);

  -- Notify the promoted person and every current leader. The actor is not
  -- excluded — a Head Pastor promoting a Leader still gets the announcement
  -- so it appears in their bell like anyone else's.
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, actor_row.id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and (p.id = target_row.id or p.is_leader = true);
end;
$$;


--
-- Name: reject_similar_reminder(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.reject_similar_reminder() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  clash record;
begin
  select id, reminder, similarity(reminder_norm, new.reminder_norm) as score
    into clash
  from public.daily_content
  where id <> new.id
    and similarity(reminder_norm, new.reminder_norm) > 0.55
  order by score desc
  limit 1;

  if found then
    raise exception
      'reminder is too similar (%.2f) to existing content %', clash.score, clash.id
      using errcode = 'unique_violation';
  end if;

  return new;
end;
$$;


--
-- Name: reminder_queue_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.reminder_queue_stats() RETURNS TABLE(pending bigint, approved bigint, rejected bigint, verses_covered bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'active'),
    count(*) filter (where status = 'rejected'),
    count(distinct verse_id) filter (where status = 'active')
  from public.daily_reminders;
$$;


--
-- Name: verses_needing_reminders(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.verses_needing_reminders(p_limit integer DEFAULT 20) RETURNS TABLE(id uuid, reference text, verse_text text, approved bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select v.id, v.reference, v.verse_text,
         count(r.id) filter (where r.status = 'active') as approved
  from public.daily_verses v
  left join public.daily_reminders r on r.verse_id = v.id
  where v.status = 'active' and v.devotional
  group by v.id, v.reference, v.verse_text
  order by approved asc, random()
  limit greatest(1, least(p_limit, 200));
$$;


--
-- Name: visible_contacts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.visible_contacts() RETURNS TABLE(id uuid, contact_number text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.id, p.contact_number
  from public.profiles p
  where p.contact_number is not null
    and (
      p.id = auth.uid()
      or is_staff()
      or p.leader_id = auth.uid()
    );
$$;


--
-- Name: FUNCTION visible_contacts(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.visible_contacts() IS 'Phone numbers the caller may see: their own, their group members, or all if staff.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bible_books; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.bible_books (
    name text NOT NULL,
    book_order smallint NOT NULL,
    testament text NOT NULL,
    chapters smallint NOT NULL,
    CONSTRAINT bible_books_testament_check CHECK ((testament = ANY (ARRAY['OT'::text, 'NT'::text]))));
ALTER TABLE public.bible_books ADD COLUMN IF NOT EXISTS name text NOT NULL;
ALTER TABLE public.bible_books ADD COLUMN IF NOT EXISTS book_order smallint NOT NULL;
ALTER TABLE public.bible_books ADD COLUMN IF NOT EXISTS testament text NOT NULL;
ALTER TABLE public.bible_books ADD COLUMN IF NOT EXISTS chapters smallint NOT NULL;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    author_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    CONSTRAINT comments_entity_type_check CHECK ((entity_type = ANY (ARRAY['post'::text, 'discussion'::text]))));
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS entity_type text NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS entity_id uuid NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS author_id uuid NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS body text NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.comments ADD COLUMN IF NOT EXISTS mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL;


--
-- Name: course_lessons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.course_lessons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    course_id uuid NOT NULL,
    ord integer DEFAULT 1 NOT NULL,
    title text NOT NULL,
    description text,
    meeting_at timestamp with time zone,
    meeting_url text,
    meeting_location text,
    slides_url text,
    assignment_title text,
    assignment_body text,
    assignment_due_at timestamp with time zone,
    todo_items text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS course_id uuid NOT NULL;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS ord integer DEFAULT 1 NOT NULL;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS meeting_at timestamp with time zone;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS meeting_url text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS meeting_location text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS slides_url text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS assignment_title text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS assignment_body text;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS assignment_due_at timestamp with time zone;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS todo_items text[] DEFAULT '{}'::text[] NOT NULL;
ALTER TABLE public.course_lessons ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    prereq_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS code text NOT NULL;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS name text NOT NULL;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS prereq_id uuid;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true NOT NULL;
ALTER TABLE public.courses ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: daily_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.daily_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    verse_id uuid NOT NULL,
    reminder_id uuid,
    assigned_on date NOT NULL,
    theme text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    visitor_id uuid,
    CONSTRAINT daily_assignments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text]))),
    CONSTRAINT one_identity CHECK ((((user_id IS NOT NULL) AND (visitor_id IS NULL)) OR ((user_id IS NULL) AND (visitor_id IS NOT NULL)))));
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS user_id uuid;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS verse_id uuid NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS reminder_id uuid;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS assigned_on date NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS theme text NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS status text DEFAULT 'active'::text NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.daily_assignments ADD COLUMN IF NOT EXISTS visitor_id uuid;


--
-- Name: daily_content; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.daily_content (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    verse_ref text NOT NULL,
    verse_text text NOT NULL,
    reminder text NOT NULL,
    theme text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reminder_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED,
    verse_ref_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(verse_ref), '[^a-z0-9: ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED,
    CONSTRAINT daily_content_status_check CHECK ((status = ANY (ARRAY['active'::text, 'retired'::text]))),
    CONSTRAINT no_em_dash CHECK (((reminder !~ '[—–]'::text) AND (verse_text !~ '[—–]'::text))),
    CONSTRAINT no_emoji CHECK ((reminder ~ '^[\x00-\x7F''’"“”]*$'::text)),
    CONSTRAINT reference_shape CHECK ((verse_ref ~ '^[1-3]? ?[A-Z][A-Za-z ]+ [0-9]{1,3}:[0-9]{1,3}(-[0-9]{1,3})?$'::text)),
    CONSTRAINT reminder_length CHECK (((array_length(regexp_split_to_array(TRIM(BOTH FROM reminder), '\s+'::text), 1) >= 50) AND (array_length(regexp_split_to_array(TRIM(BOTH FROM reminder), '\s+'::text), 1) <= 90))));
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS verse_ref text NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS verse_text text NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS reminder text NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS theme text NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS status text DEFAULT 'active'::text NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS reminder_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED;
ALTER TABLE public.daily_content ADD COLUMN IF NOT EXISTS verse_ref_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(verse_ref), '[^a-z0-9: ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED;


--
-- Name: daily_reminders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.daily_reminders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reminder text NOT NULL,
    theme text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reminder_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED,
    verse_id uuid,
    focus_tag text,
    template_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    source text DEFAULT 'library'::text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    model text,
    CONSTRAINT daily_reminders_source_check CHECK ((source = ANY (ARRAY['library'::text, 'generated'::text]))),
    CONSTRAINT daily_reminders_status_check CHECK ((status = ANY (ARRAY['active'::text, 'pending'::text, 'rejected'::text, 'retired'::text]))),
    CONSTRAINT reminder_clean_spacing CHECK (((reminder !~ '  '::text) AND (reminder !~ '[.!?] +[a-z]'::text))),
    CONSTRAINT reminder_ends_stop CHECK ((reminder ~ '[.!?]$'::text)),
    CONSTRAINT reminder_no_em_dash CHECK ((reminder !~ '[—–]'::text)),
    CONSTRAINT reminder_no_emoji CHECK ((reminder ~ '^[\x00-\x7F''’"“”]*$'::text)),
    CONSTRAINT reminder_no_hashtag CHECK ((reminder !~ '#'::text)),
    CONSTRAINT reminder_starts_capital CHECK ((reminder ~ '^[A-Z]'::text)));
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS reminder text NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS theme text NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS status text DEFAULT 'active'::text NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS reminder_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reminder), '[^a-z0-9 ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS verse_id uuid;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS focus_tag text;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS template_id uuid;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS source text DEFAULT 'library'::text NOT NULL;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS reviewed_by uuid;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS reviewed_at timestamp with time zone;
ALTER TABLE public.daily_reminders ADD COLUMN IF NOT EXISTS model text;


--
-- Name: COLUMN daily_reminders.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.daily_reminders.source IS 'library: written by a person. generated: written by a model and reviewed before use.';


--
-- Name: daily_verses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.daily_verses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reference text NOT NULL,
    verse_text text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    reference_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reference), '[^a-z0-9: ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED,
    devotional boolean DEFAULT true NOT NULL,
    book text,
    book_order smallint,
    chapter smallint,
    verse smallint,
    testament text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT daily_verses_status_check CHECK ((status = ANY (ARRAY['active'::text, 'retired'::text]))),
    CONSTRAINT daily_verses_testament_check CHECK ((testament = ANY (ARRAY['OT'::text, 'NT'::text]))),
    CONSTRAINT verse_no_em_dash CHECK ((verse_text !~ '[—–]'::text)),
    CONSTRAINT verse_reference_is_real CHECK (public.is_valid_bible_reference(reference)));
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS reference text NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS verse_text text NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS status text DEFAULT 'active'::text NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS reference_norm text GENERATED ALWAYS AS (TRIM(BOTH FROM regexp_replace(regexp_replace(lower(reference), '[^a-z0-9: ]'::text, ' '::text, 'g'::text), '\s+'::text, ' '::text, 'g'::text))) STORED;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS devotional boolean DEFAULT true NOT NULL;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS book text;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS book_order smallint;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS chapter smallint;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS verse smallint;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS testament text;
ALTER TABLE public.daily_verses ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: COLUMN daily_verses.devotional; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.daily_verses.devotional IS 'Eligible for the daily draw. Cleared for verse lists, genealogies and fragments.';


--
-- Name: devotional_books; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.devotional_books (
    name text NOT NULL);
ALTER TABLE public.devotional_books ADD COLUMN IF NOT EXISTS name text NOT NULL;


--
-- Name: discussions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.discussions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    status public.approval_status DEFAULT 'pending'::public.approval_status NOT NULL,
    moderated_by uuid,
    moderated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL);
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS author_id uuid NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS body text NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS status public.approval_status DEFAULT 'pending'::public.approval_status NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS moderated_by uuid;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS moderated_at timestamp with time zone;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.discussions ADD COLUMN IF NOT EXISTS mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL;


--
-- Name: enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    course_id uuid NOT NULL,
    status public.enrollment_status DEFAULT 'enrolled'::public.enrollment_status NOT NULL,
    enrolled_by uuid,
    enrolled_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    notes text);
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS user_id uuid NOT NULL;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS course_id uuid NOT NULL;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS status public.enrollment_status DEFAULT 'enrolled'::public.enrollment_status NOT NULL;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS enrolled_by uuid;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS enrolled_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone;
ALTER TABLE public.enrollments ADD COLUMN IF NOT EXISTS notes text;


--
-- Name: event_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.event_interests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.event_interests ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.event_interests ADD COLUMN IF NOT EXISTS event_id uuid NOT NULL;
ALTER TABLE public.event_interests ADD COLUMN IF NOT EXISTS profile_id uuid NOT NULL;
ALTER TABLE public.event_interests ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone,
    location text,
    cover_url text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS starts_at timestamp with time zone NOT NULL;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ends_at timestamp with time zone;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS cover_url text;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: hero_slides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.hero_slides (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    image_url text NOT NULL,
    caption text,
    ord integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS image_url text NOT NULL;
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS caption text;
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS ord integer DEFAULT 1 NOT NULL;
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true NOT NULL;
ALTER TABLE public.hero_slides ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: lesson_completions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.lesson_completions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enrollment_id uuid NOT NULL,
    lesson_id uuid NOT NULL,
    verified_by uuid,
    verified_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text);
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS enrollment_id uuid NOT NULL;
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS lesson_id uuid NOT NULL;
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS verified_by uuid;
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS verified_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.lesson_completions ADD COLUMN IF NOT EXISTS notes text;


--
-- Name: live_series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.live_series (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    cover_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.live_series ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.live_series ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.live_series ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.live_series ADD COLUMN IF NOT EXISTS cover_url text;
ALTER TABLE public.live_series ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: live_videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.live_videos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    video_url text NOT NULL,
    occurred_on date NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    series_id uuid);
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS video_url text NOT NULL;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS occurred_on date NOT NULL;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.live_videos ADD COLUMN IF NOT EXISTS series_id uuid;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    body text NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_id uuid NOT NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS recipient_id uuid NOT NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS body text NOT NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_at timestamp with time zone;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: ministries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.ministries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    summary text NOT NULL,
    calling text NOT NULL,
    scripture text NOT NULL,
    scripture_ref text NOT NULL,
    duties text[] DEFAULT '{}'::text[] NOT NULL,
    leader_id uuid,
    sort integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS slug text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS name text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS summary text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS calling text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS scripture text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS scripture_ref text NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS duties text[] DEFAULT '{}'::text[] NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS leader_id uuid;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS sort integer DEFAULT 0 NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true NOT NULL;
ALTER TABLE public.ministries ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: ministry_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.ministry_interests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ministry_id uuid NOT NULL,
    profile_id uuid NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    status public.ministry_status DEFAULT 'interested'::public.ministry_status NOT NULL,
    decided_at timestamp with time zone,
    decided_by uuid,
    role_in_team text);
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS ministry_id uuid NOT NULL;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS profile_id uuid NOT NULL;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS status public.ministry_status DEFAULT 'interested'::public.ministry_status NOT NULL;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS decided_at timestamp with time zone;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS decided_by uuid;
ALTER TABLE public.ministry_interests ADD COLUMN IF NOT EXISTS role_in_team text;


--
-- Name: COLUMN ministry_interests.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ministry_interests.status IS 'interested: put their hand up. member: serving. declined: not this season.';


--
-- Name: COLUMN ministry_interests.role_in_team; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ministry_interests.role_in_team IS 'Optional, e.g. "Sound" or "Front door". Shown beside the name on the team list.';


--
-- Name: news_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.news_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    media_urls text[] DEFAULT '{}'::text[] NOT NULL,
    video_url text,
    author_id uuid,
    published_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS title text NOT NULL;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS body text NOT NULL;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS media_urls text[] DEFAULT '{}'::text[] NOT NULL;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS video_url text;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS author_id uuid;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS published_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.news_posts ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: notification_mutes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.notification_mutes (
    muter_id uuid NOT NULL,
    muted_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT no_self_mute CHECK ((muter_id <> muted_id)));
ALTER TABLE public.notification_mutes ADD COLUMN IF NOT EXISTS muter_id uuid NOT NULL;
ALTER TABLE public.notification_mutes ADD COLUMN IF NOT EXISTS muted_id uuid NOT NULL;
ALTER TABLE public.notification_mutes ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    actor_id uuid,
    kind public.notification_kind NOT NULL,
    entity_type text,
    entity_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS user_id uuid NOT NULL;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS actor_id uuid;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS kind public.notification_kind NOT NULL;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS entity_type text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS entity_id uuid;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb NOT NULL;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS read_at timestamp with time zone;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    title text,
    body text NOT NULL,
    media_url text,
    status public.approval_status DEFAULT 'approved'::public.approval_status NOT NULL,
    moderated_by uuid,
    moderated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    is_system boolean DEFAULT false NOT NULL);
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS author_id uuid NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS body text NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS media_url text;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS status public.approval_status DEFAULT 'approved'::public.approval_status NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS moderated_by uuid;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS moderated_at timestamp with time zone;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_system boolean DEFAULT false NOT NULL;


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    role public.user_role DEFAULT 'user'::public.user_role NOT NULL,
    account_status public.approval_status DEFAULT 'pending'::public.approval_status NOT NULL,
    avatar_url text,
    contact_number text,
    leader_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_leader boolean DEFAULT false NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL,
    facebook_url text,
    instagram_url text,
    terms_accepted_at timestamp with time zone,
    terms_accepted_version text,
    title text,
    is_hidden boolean DEFAULT false NOT NULL,
    CONSTRAINT profiles_facebook_url_check CHECK (((facebook_url IS NULL) OR (facebook_url ~* '^https://([a-z0-9-]+\.)*facebook\.com/.+'::text))),
    CONSTRAINT profiles_instagram_url_check CHECK (((instagram_url IS NULL) OR (instagram_url ~* '^https://([a-z0-9-]+\.)*instagram\.com/.+'::text))));
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS id uuid NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name text NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email text NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role public.user_role DEFAULT 'user'::public.user_role NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_status public.approval_status DEFAULT 'pending'::public.approval_status NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS contact_number text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS leader_id uuid;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_leader boolean DEFAULT false NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS must_change_password boolean DEFAULT false NOT NULL;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS facebook_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS instagram_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS terms_accepted_at timestamp with time zone;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS terms_accepted_version text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_hidden boolean DEFAULT false NOT NULL;


--
-- Name: COLUMN profiles.facebook_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.facebook_url IS 'Full https URL to the member''s Facebook profile.';


--
-- Name: COLUMN profiles.instagram_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.instagram_url IS 'Full https URL to the member''s Instagram profile.';


--
-- Name: COLUMN profiles.terms_accepted_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.terms_accepted_at IS 'When this member accepted the information agreement. Null means never.';


--
-- Name: COLUMN profiles.terms_accepted_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.terms_accepted_version IS 'Which version of the agreement text they accepted.';


--
-- Name: COLUMN profiles.title; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.title IS 'What this person is called in the church, e.g. Head Pastor. Shown on the org chart.';


--
-- Name: COLUMN profiles.is_hidden; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.profiles.is_hidden IS 'Service account. Hidden from directories and the org chart; only a super admin sees it.';


--
-- Name: reactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.reactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    user_id uuid NOT NULL,
    emoji text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reactions_emoji_check CHECK ((char_length(emoji) <= 8)),
    CONSTRAINT reactions_entity_type_check CHECK ((entity_type = ANY (ARRAY['post'::text, 'discussion'::text, 'comment'::text]))));
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS entity_type text NOT NULL;
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS entity_id uuid NOT NULL;
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS user_id uuid NOT NULL;
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS emoji text NOT NULL;
ALTER TABLE public.reactions ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;


--
-- Name: reminder_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.reminder_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opening text DEFAULT ''::text,
    body text DEFAULT ''::text,
    closing text DEFAULT ''::text,
    focus_tag text NOT NULL,
    tone text DEFAULT 'steady'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    text text NOT NULL,
    CONSTRAINT reminder_templates_status_check CHECK ((status = ANY (ARRAY['active'::text, 'retired'::text]))),
    CONSTRAINT reminder_templates_tone_check CHECK ((tone = ANY (ARRAY['steady'::text, 'gentle'::text, 'direct'::text]))),
    CONSTRAINT template_clean_spacing CHECK (((text !~ '  '::text) AND (text !~ '[.!?] +[a-z]'::text))),
    CONSTRAINT template_ends_stop CHECK (((text IS NULL) OR (text ~ '[.!?]$'::text))),
    CONSTRAINT template_no_em_dash CHECK ((((opening || body) || closing) !~ '[—–]'::text)),
    CONSTRAINT template_no_emoji CHECK ((((opening || body) || closing) ~ '^[\x00-\x7F''’"“”]*$'::text)),
    CONSTRAINT template_no_roles CHECK ((((((opening || ' '::text) || body) || ' '::text) || closing) !~* '\m(parent|parents|mother|father|mum|dad|student|students|employee|employees|husband|wife|spouse|teenager|child of yours|your kids|your children|your job|your boss)\M'::text)),
    CONSTRAINT template_starts_capital CHECK (((text IS NULL) OR (text ~ '^[A-Z]'::text))));
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid() NOT NULL;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS opening text DEFAULT ''::text;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS body text DEFAULT ''::text;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS closing text DEFAULT ''::text;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS focus_tag text NOT NULL;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS tone text DEFAULT 'steady'::text NOT NULL;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS status text DEFAULT 'active'::text NOT NULL;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.reminder_templates ADD COLUMN IF NOT EXISTS text text NOT NULL;


--
-- Name: site_content; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.site_content (
    slug text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid);
ALTER TABLE public.site_content ADD COLUMN IF NOT EXISTS slug text NOT NULL;
ALTER TABLE public.site_content ADD COLUMN IF NOT EXISTS body text DEFAULT ''::text NOT NULL;
ALTER TABLE public.site_content ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL;
ALTER TABLE public.site_content ADD COLUMN IF NOT EXISTS updated_by uuid;


--
-- Name: TABLE site_content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.site_content IS 'Editable copy blocks keyed by slug. Rendered by getContent() with a code-side fallback.';


--
-- Name: verse_topic_kinds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.verse_topic_kinds (
    slug text NOT NULL,
    label text NOT NULL,
    visitor_safe boolean DEFAULT false NOT NULL);
ALTER TABLE public.verse_topic_kinds ADD COLUMN IF NOT EXISTS slug text NOT NULL;
ALTER TABLE public.verse_topic_kinds ADD COLUMN IF NOT EXISTS label text NOT NULL;
ALTER TABLE public.verse_topic_kinds ADD COLUMN IF NOT EXISTS visitor_safe boolean DEFAULT false NOT NULL;


--
-- Name: verse_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.verse_topics (
    verse_id uuid NOT NULL,
    topic text NOT NULL);
ALTER TABLE public.verse_topics ADD COLUMN IF NOT EXISTS verse_id uuid NOT NULL;
ALTER TABLE public.verse_topics ADD COLUMN IF NOT EXISTS topic text NOT NULL;


--
-- Name: bible_books bible_books_book_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.bible_books
    ADD CONSTRAINT bible_books_book_order_key UNIQUE (book_order);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: bible_books bible_books_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.bible_books
    ADD CONSTRAINT bible_books_pkey PRIMARY KEY (name);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: course_lessons course_lessons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.course_lessons
    ADD CONSTRAINT course_lessons_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: courses courses_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_code_key UNIQUE (code);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_assignments daily_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_assignments
    ADD CONSTRAINT daily_assignments_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_content daily_content_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_content
    ADD CONSTRAINT daily_content_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_reminders daily_reminders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_reminders
    ADD CONSTRAINT daily_reminders_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_verses daily_verses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_verses
    ADD CONSTRAINT daily_verses_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: devotional_books devotional_books_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.devotional_books
    ADD CONSTRAINT devotional_books_pkey PRIMARY KEY (name);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: discussions discussions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.discussions
    ADD CONSTRAINT discussions_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: enrollments enrollments_user_id_course_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_user_id_course_id_key UNIQUE (user_id, course_id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: event_interests event_interests_event_id_profile_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.event_interests
    ADD CONSTRAINT event_interests_event_id_profile_id_key UNIQUE (event_id, profile_id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: event_interests event_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.event_interests
    ADD CONSTRAINT event_interests_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: hero_slides hero_slides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.hero_slides
    ADD CONSTRAINT hero_slides_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: lesson_completions lesson_completions_enrollment_id_lesson_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.lesson_completions
    ADD CONSTRAINT lesson_completions_enrollment_id_lesson_id_key UNIQUE (enrollment_id, lesson_id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: lesson_completions lesson_completions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.lesson_completions
    ADD CONSTRAINT lesson_completions_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: live_series live_series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.live_series
    ADD CONSTRAINT live_series_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: live_series live_series_title_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.live_series
    ADD CONSTRAINT live_series_title_key UNIQUE (title);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: live_videos live_videos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.live_videos
    ADD CONSTRAINT live_videos_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministries ministries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministries
    ADD CONSTRAINT ministries_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministries ministries_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministries
    ADD CONSTRAINT ministries_slug_key UNIQUE (slug);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministry_interests ministry_interests_ministry_id_profile_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministry_interests
    ADD CONSTRAINT ministry_interests_ministry_id_profile_id_key UNIQUE (ministry_id, profile_id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministry_interests ministry_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministry_interests
    ADD CONSTRAINT ministry_interests_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: news_posts news_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.news_posts
    ADD CONSTRAINT news_posts_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notification_mutes notification_mutes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notification_mutes
    ADD CONSTRAINT notification_mutes_pkey PRIMARY KEY (muter_id, muted_id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: profiles profiles_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_email_key UNIQUE (email);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: reactions reactions_entity_type_entity_id_user_id_emoji_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.reactions
    ADD CONSTRAINT reactions_entity_type_entity_id_user_id_emoji_key UNIQUE (entity_type, entity_id, user_id, emoji);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: reactions reactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.reactions
    ADD CONSTRAINT reactions_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: reminder_templates reminder_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.reminder_templates
    ADD CONSTRAINT reminder_templates_pkey PRIMARY KEY (id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: site_content site_content_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.site_content
    ADD CONSTRAINT site_content_pkey PRIMARY KEY (slug);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: verse_topic_kinds verse_topic_kinds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.verse_topic_kinds
    ADD CONSTRAINT verse_topic_kinds_pkey PRIMARY KEY (slug);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: verse_topics verse_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.verse_topics
    ADD CONSTRAINT verse_topics_pkey PRIMARY KEY (verse_id, topic);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: assignments_reminder_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS assignments_reminder_uniq ON public.daily_assignments USING btree (reminder_id);


--
-- Name: assignments_user_day_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS assignments_user_day_uniq ON public.daily_assignments USING btree (user_id, assigned_on) WHERE (user_id IS NOT NULL);


--
-- Name: assignments_visitor_day_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS assignments_visitor_day_uniq ON public.daily_assignments USING btree (visitor_id, assigned_on) WHERE (visitor_id IS NOT NULL);


--
-- Name: comments_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS comments_entity_idx ON public.comments USING btree (entity_type, entity_id, created_at);


--
-- Name: course_lessons_course_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS course_lessons_course_idx ON public.course_lessons USING btree (course_id, ord);


--
-- Name: daily_assignments_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_assignments_user_idx ON public.daily_assignments USING btree (user_id, assigned_on DESC);


--
-- Name: daily_assignments_verse_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_assignments_verse_idx ON public.daily_assignments USING btree (verse_id, assigned_on DESC);


--
-- Name: daily_content_reminder_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_content_reminder_trgm ON public.daily_content USING gin (reminder_norm public.gin_trgm_ops);


--
-- Name: daily_content_reminder_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS daily_content_reminder_uniq ON public.daily_content USING btree (reminder_norm);


--
-- Name: daily_content_verse_ref_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS daily_content_verse_ref_uniq ON public.daily_content USING btree (verse_ref_norm);


--
-- Name: daily_reminders_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_reminders_pending_idx ON public.daily_reminders USING btree (created_at) WHERE (status = 'pending'::text);


--
-- Name: daily_reminders_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_reminders_trgm ON public.daily_reminders USING gin (reminder_norm public.gin_trgm_ops);


--
-- Name: daily_reminders_verse_norm_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS daily_reminders_verse_norm_uniq ON public.daily_reminders USING btree (verse_id, reminder_norm);


--
-- Name: daily_reminders_verse_unused_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_reminders_verse_unused_idx ON public.daily_reminders USING btree (verse_id) WHERE (status = 'active'::text);


--
-- Name: daily_verses_bcv_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS daily_verses_bcv_uniq ON public.daily_verses USING btree (book, chapter, verse) WHERE (book IS NOT NULL);


--
-- Name: daily_verses_devotional_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_verses_devotional_idx ON public.daily_verses USING btree (devotional) WHERE (status = 'active'::text);


--
-- Name: daily_verses_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS daily_verses_order_idx ON public.daily_verses USING btree (book_order, chapter, verse);


--
-- Name: daily_verses_reference_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS daily_verses_reference_uniq ON public.daily_verses USING btree (reference_norm);


--
-- Name: discussions_status_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS discussions_status_created_idx ON public.discussions USING btree (status, created_at DESC);


--
-- Name: enrollments_course_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS enrollments_course_idx ON public.enrollments USING btree (course_id);


--
-- Name: enrollments_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS enrollments_user_idx ON public.enrollments USING btree (user_id);


--
-- Name: event_interests_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS event_interests_event_idx ON public.event_interests USING btree (event_id, created_at DESC);


--
-- Name: hero_slides_ord_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS hero_slides_ord_idx ON public.hero_slides USING btree (ord);


--
-- Name: lesson_completions_enrollment_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS lesson_completions_enrollment_idx ON public.lesson_completions USING btree (enrollment_id);


--
-- Name: live_videos_occurred_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS live_videos_occurred_idx ON public.live_videos USING btree (occurred_on DESC);


--
-- Name: live_videos_series_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS live_videos_series_idx ON public.live_videos USING btree (series_id);


--
-- Name: messages_recipient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS messages_recipient_idx ON public.messages USING btree (recipient_id, created_at DESC);


--
-- Name: ministry_interests_ministry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS ministry_interests_ministry_idx ON public.ministry_interests USING btree (ministry_id, created_at DESC);


--
-- Name: ministry_interests_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS ministry_interests_status_idx ON public.ministry_interests USING btree (ministry_id, status);


--
-- Name: news_posts_published_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS news_posts_published_idx ON public.news_posts USING btree (published_at DESC);


--
-- Name: notifications_recipient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS notifications_recipient_idx ON public.notifications USING btree (user_id, created_at DESC);


--
-- Name: notifications_unread_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS notifications_unread_idx ON public.notifications USING btree (user_id) WHERE (read_at IS NULL);


--
-- Name: posts_status_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS posts_status_created_idx ON public.posts USING btree (status, created_at DESC);


--
-- Name: profiles_is_leader_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS profiles_is_leader_idx ON public.profiles USING btree (is_leader);


--
-- Name: profiles_leader_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS profiles_leader_idx ON public.profiles USING btree (leader_id);


--
-- Name: reactions_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS reactions_entity_idx ON public.reactions USING btree (entity_type, entity_id);


--
-- Name: reminder_templates_text_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS reminder_templates_text_uniq ON public.reminder_templates USING btree (md5(lower(regexp_replace(text, '\s+'::text, ' '::text, 'g'::text))));


--
-- Name: verse_topics_topic_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX IF NOT EXISTS verse_topics_topic_idx ON public.verse_topics USING btree (topic);


--
-- Name: comments comments_notify; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS comments_notify ON public.comments;
CREATE TRIGGER comments_notify AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.notify_comment();


--
-- Name: daily_content daily_content_similarity; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS daily_content_similarity ON public.daily_content;
CREATE TRIGGER daily_content_similarity BEFORE INSERT OR UPDATE OF reminder ON public.daily_content FOR EACH ROW EXECUTE FUNCTION public.reject_similar_reminder();


--
-- Name: daily_reminders daily_reminders_similarity; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS daily_reminders_similarity ON public.daily_reminders;
CREATE TRIGGER daily_reminders_similarity BEFORE INSERT OR UPDATE OF reminder ON public.daily_reminders FOR EACH ROW EXECUTE FUNCTION public.reject_similar_reminder();


--
-- Name: discussions discussions_notify_mentions; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS discussions_notify_mentions ON public.discussions;
CREATE TRIGGER discussions_notify_mentions AFTER INSERT ON public.discussions FOR EACH ROW EXECUTE FUNCTION public.notify_post_mentions();


--
-- Name: enrollments enrollments_notify; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS enrollments_notify ON public.enrollments;
CREATE TRIGGER enrollments_notify AFTER INSERT ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.notify_enrollment();


--
-- Name: lesson_completions lesson_completions_notify; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS lesson_completions_notify ON public.lesson_completions;
CREATE TRIGGER lesson_completions_notify AFTER INSERT ON public.lesson_completions FOR EACH ROW EXECUTE FUNCTION public.notify_lesson_verified();


--
-- Name: event_interests on_event_interest; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_event_interest ON public.event_interests;
CREATE TRIGGER on_event_interest AFTER INSERT ON public.event_interests FOR EACH ROW EXECUTE FUNCTION public.notify_event_interest();


--
-- Name: ministry_interests on_ministry_interest; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_ministry_interest ON public.ministry_interests;
CREATE TRIGGER on_ministry_interest AFTER INSERT ON public.ministry_interests FOR EACH ROW EXECUTE FUNCTION public.notify_ministry_interest();


--
-- Name: discussions on_new_discussion; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_new_discussion ON public.discussions;
CREATE TRIGGER on_new_discussion AFTER INSERT ON public.discussions FOR EACH ROW EXECUTE FUNCTION public.notify_new_discussion();


--
-- Name: events on_new_event; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_new_event ON public.events;
CREATE TRIGGER on_new_event AFTER INSERT ON public.events FOR EACH ROW EXECUTE FUNCTION public.notify_new_event();


--
-- Name: news_posts on_new_news; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_new_news ON public.news_posts;
CREATE TRIGGER on_new_news AFTER INSERT ON public.news_posts FOR EACH ROW EXECUTE FUNCTION public.notify_new_news();


--
-- Name: posts on_new_post; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_new_post ON public.posts;
CREATE TRIGGER on_new_post AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.notify_new_post();


--
-- Name: posts on_post_approved; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS on_post_approved ON public.posts;
CREATE TRIGGER on_post_approved AFTER UPDATE OF status ON public.posts FOR EACH ROW EXECUTE FUNCTION public.notify_post_approved();


--
-- Name: posts posts_notify_mentions; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS posts_notify_mentions ON public.posts;
CREATE TRIGGER posts_notify_mentions AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.notify_post_mentions();


--
-- Name: reactions reactions_notify; Type: TRIGGER; Schema: public; Owner: -
--

DROP TRIGGER IF EXISTS reactions_notify ON public.reactions;
CREATE TRIGGER reactions_notify AFTER INSERT ON public.reactions FOR EACH ROW EXECUTE FUNCTION public.notify_reaction();


--
-- Name: comments comments_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: course_lessons course_lessons_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.course_lessons
    ADD CONSTRAINT course_lessons_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: courses courses_prereq_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_prereq_id_fkey FOREIGN KEY (prereq_id) REFERENCES public.courses(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_assignments daily_assignments_reminder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_assignments
    ADD CONSTRAINT daily_assignments_reminder_id_fkey FOREIGN KEY (reminder_id) REFERENCES public.daily_reminders(id) ON DELETE RESTRICT;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_assignments daily_assignments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_assignments
    ADD CONSTRAINT daily_assignments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_assignments daily_assignments_verse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_assignments
    ADD CONSTRAINT daily_assignments_verse_id_fkey FOREIGN KEY (verse_id) REFERENCES public.daily_verses(id) ON DELETE RESTRICT;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_reminders daily_reminders_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_reminders
    ADD CONSTRAINT daily_reminders_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_reminders daily_reminders_template_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_reminders
    ADD CONSTRAINT daily_reminders_template_fk FOREIGN KEY (template_id) REFERENCES public.reminder_templates(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_reminders daily_reminders_verse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_reminders
    ADD CONSTRAINT daily_reminders_verse_id_fkey FOREIGN KEY (verse_id) REFERENCES public.daily_verses(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: devotional_books devotional_books_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.devotional_books
    ADD CONSTRAINT devotional_books_name_fkey FOREIGN KEY (name) REFERENCES public.bible_books(name);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: discussions discussions_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.discussions
    ADD CONSTRAINT discussions_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: discussions discussions_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.discussions
    ADD CONSTRAINT discussions_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: enrollments enrollments_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: enrollments enrollments_enrolled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_enrolled_by_fkey FOREIGN KEY (enrolled_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: enrollments enrollments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: event_interests event_interests_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.event_interests
    ADD CONSTRAINT event_interests_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: event_interests event_interests_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.event_interests
    ADD CONSTRAINT event_interests_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: events events_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: lesson_completions lesson_completions_enrollment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.lesson_completions
    ADD CONSTRAINT lesson_completions_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.enrollments(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: lesson_completions lesson_completions_lesson_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.lesson_completions
    ADD CONSTRAINT lesson_completions_lesson_id_fkey FOREIGN KEY (lesson_id) REFERENCES public.course_lessons(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: lesson_completions lesson_completions_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.lesson_completions
    ADD CONSTRAINT lesson_completions_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: live_videos live_videos_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.live_videos
    ADD CONSTRAINT live_videos_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: live_videos live_videos_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.live_videos
    ADD CONSTRAINT live_videos_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.live_series(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: messages messages_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministries ministries_leader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministries
    ADD CONSTRAINT ministries_leader_id_fkey FOREIGN KEY (leader_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministry_interests ministry_interests_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministry_interests
    ADD CONSTRAINT ministry_interests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministry_interests ministry_interests_ministry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministry_interests
    ADD CONSTRAINT ministry_interests_ministry_id_fkey FOREIGN KEY (ministry_id) REFERENCES public.ministries(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: ministry_interests ministry_interests_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.ministry_interests
    ADD CONSTRAINT ministry_interests_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: news_posts news_posts_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.news_posts
    ADD CONSTRAINT news_posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notification_mutes notification_mutes_muted_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notification_mutes
    ADD CONSTRAINT notification_mutes_muted_id_fkey FOREIGN KEY (muted_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notification_mutes notification_mutes_muter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notification_mutes
    ADD CONSTRAINT notification_mutes_muter_id_fkey FOREIGN KEY (muter_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notifications notifications_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: posts posts_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: posts posts_moderated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_moderated_by_fkey FOREIGN KEY (moderated_by) REFERENCES public.profiles(id);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: profiles profiles_leader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_leader_id_fkey FOREIGN KEY (leader_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: reactions reactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.reactions
    ADD CONSTRAINT reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: site_content site_content_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.site_content
    ADD CONSTRAINT site_content_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: daily_verses verse_book_is_canonical; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.daily_verses
    ADD CONSTRAINT verse_book_is_canonical FOREIGN KEY (book) REFERENCES public.bible_books(name);
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: verse_topics verse_topics_topic_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.verse_topics
    ADD CONSTRAINT verse_topics_topic_fkey FOREIGN KEY (topic) REFERENCES public.verse_topic_kinds(slug) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: verse_topics verse_topics_verse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $ddo$ BEGIN
ALTER TABLE ONLY public.verse_topics
    ADD CONSTRAINT verse_topics_verse_id_fkey FOREIGN KEY (verse_id) REFERENCES public.daily_verses(id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN null; END $ddo$;


--
-- Name: notification_mutes a mute belongs to the person who set it; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "a mute belongs to the person who set it" ON public.notification_mutes;
CREATE POLICY "a mute belongs to the person who set it" ON public.notification_mutes USING ((muter_id = auth.uid())) WITH CHECK ((muter_id = auth.uid()));


--
-- Name: courses admins manage courses; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage courses" ON public.courses;
CREATE POLICY "admins manage courses" ON public.courses USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: enrollments admins manage enrollments; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage enrollments" ON public.enrollments;
CREATE POLICY "admins manage enrollments" ON public.enrollments USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: hero_slides admins manage hero slides; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage hero slides" ON public.hero_slides;
CREATE POLICY "admins manage hero slides" ON public.hero_slides USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: course_lessons admins manage lessons; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage lessons" ON public.course_lessons;
CREATE POLICY "admins manage lessons" ON public.course_lessons USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: ministries admins manage ministries; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage ministries" ON public.ministries;
CREATE POLICY "admins manage ministries" ON public.ministries USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: news_posts admins manage news; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage news" ON public.news_posts;
CREATE POLICY "admins manage news" ON public.news_posts USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: profiles admins manage profiles; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins manage profiles" ON public.profiles;
CREATE POLICY "admins manage profiles" ON public.profiles USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: lesson_completions admins verify completions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "admins verify completions" ON public.lesson_completions;
CREATE POLICY "admins verify completions" ON public.lesson_completions USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: comments approved users comment; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "approved users comment" ON public.comments;
CREATE POLICY "approved users comment" ON public.comments FOR INSERT WITH CHECK (((author_id = auth.uid()) AND public.is_approved() AND (((entity_type = 'post'::text) AND (EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = comments.entity_id) AND (p.status = 'approved'::public.approval_status))))) OR ((entity_type = 'discussion'::text) AND (EXISTS ( SELECT 1
   FROM public.discussions d
  WHERE ((d.id = comments.entity_id) AND (d.status = 'approved'::public.approval_status))))))));


--
-- Name: discussions approved users create discussions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "approved users create discussions" ON public.discussions;
CREATE POLICY "approved users create discussions" ON public.discussions FOR INSERT WITH CHECK (((author_id = auth.uid()) AND public.is_approved()));


--
-- Name: posts approved users create posts; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "approved users create posts" ON public.posts;
CREATE POLICY "approved users create posts" ON public.posts FOR INSERT WITH CHECK (((author_id = auth.uid()) AND public.is_approved()));


--
-- Name: reactions approved users react; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "approved users react" ON public.reactions;
CREATE POLICY "approved users react" ON public.reactions FOR INSERT WITH CHECK (((user_id = auth.uid()) AND public.is_approved()));


--
-- Name: messages approved users send messages; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "approved users send messages" ON public.messages;
CREATE POLICY "approved users send messages" ON public.messages FOR INSERT WITH CHECK (((sender_id = auth.uid()) AND public.is_approved()));


--
-- Name: daily_assignments assignments are private; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "assignments are private" ON public.daily_assignments;
CREATE POLICY "assignments are private" ON public.daily_assignments FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: comments author or staff deletes comment; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "author or staff deletes comment" ON public.comments;
CREATE POLICY "author or staff deletes comment" ON public.comments FOR DELETE USING (((author_id = auth.uid()) OR public.is_staff()));


--
-- Name: posts author updates own pending; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "author updates own pending" ON public.posts;
CREATE POLICY "author updates own pending" ON public.posts FOR UPDATE USING (((author_id = auth.uid()) AND (status = 'pending'::public.approval_status))) WITH CHECK ((author_id = auth.uid()));


--
-- Name: discussions author updates own pending discussion; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "author updates own pending discussion" ON public.discussions;
CREATE POLICY "author updates own pending discussion" ON public.discussions FOR UPDATE USING (((author_id = auth.uid()) AND (status = 'pending'::public.approval_status))) WITH CHECK ((author_id = auth.uid()));


--
-- Name: comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

--
-- Name: course_lessons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.course_lessons ENABLE ROW LEVEL SECURITY;

--
-- Name: courses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_reminders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_reminders ENABLE ROW LEVEL SECURITY;

--
-- Name: daily_verses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.daily_verses ENABLE ROW LEVEL SECURITY;

--
-- Name: discussions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.discussions ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

--
-- Name: event_interests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_interests ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: courses everyone reads active courses; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads active courses" ON public.courses;
CREATE POLICY "everyone reads active courses" ON public.courses FOR SELECT USING ((is_active OR public.is_staff()));


--
-- Name: events everyone reads events; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads events" ON public.events;
CREATE POLICY "everyone reads events" ON public.events FOR SELECT USING (true);


--
-- Name: hero_slides everyone reads hero slides; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads hero slides" ON public.hero_slides;
CREATE POLICY "everyone reads hero slides" ON public.hero_slides FOR SELECT USING ((is_active OR public.is_admin()));


--
-- Name: course_lessons everyone reads lessons of active courses; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads lessons of active courses" ON public.course_lessons;
CREATE POLICY "everyone reads lessons of active courses" ON public.course_lessons FOR SELECT USING ((public.is_staff() OR (EXISTS ( SELECT 1
   FROM public.courses c
  WHERE ((c.id = course_lessons.course_id) AND c.is_active)))));


--
-- Name: live_series everyone reads live series; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads live series" ON public.live_series;
CREATE POLICY "everyone reads live series" ON public.live_series FOR SELECT USING (true);


--
-- Name: live_videos everyone reads live videos; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads live videos" ON public.live_videos;
CREATE POLICY "everyone reads live videos" ON public.live_videos FOR SELECT USING (true);


--
-- Name: news_posts everyone reads news; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "everyone reads news" ON public.news_posts;
CREATE POLICY "everyone reads news" ON public.news_posts FOR SELECT USING (true);


--
-- Name: hero_slides; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hero_slides ENABLE ROW LEVEL SECURITY;

--
-- Name: ministry_interests leaders decide ministry membership; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "leaders decide ministry membership" ON public.ministry_interests;
CREATE POLICY "leaders decide ministry membership" ON public.ministry_interests FOR UPDATE USING (public.can_manage_ministry(ministry_id)) WITH CHECK (public.can_manage_ministry(ministry_id));


--
-- Name: lesson_completions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lesson_completions ENABLE ROW LEVEL SECURITY;

--
-- Name: live_series; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.live_series ENABLE ROW LEVEL SECURITY;

--
-- Name: live_videos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.live_videos ENABLE ROW LEVEL SECURITY;

--
-- Name: event_interests members mark themselves interested; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members mark themselves interested" ON public.event_interests;
CREATE POLICY "members mark themselves interested" ON public.event_interests FOR INSERT WITH CHECK (((profile_id = auth.uid()) AND public.is_approved()));


--
-- Name: ministries members read active ministries; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members read active ministries" ON public.ministries;
CREATE POLICY "members read active ministries" ON public.ministries FOR SELECT USING ((((is_active = true) AND public.is_approved()) OR public.is_staff()));


--
-- Name: ministry_interests members record their own interest; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members record their own interest" ON public.ministry_interests;
CREATE POLICY "members record their own interest" ON public.ministry_interests FOR INSERT WITH CHECK (((profile_id = auth.uid()) AND public.is_approved()));


--
-- Name: event_interests members see who is coming; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members see who is coming" ON public.event_interests;
CREATE POLICY "members see who is coming" ON public.event_interests FOR SELECT USING ((public.is_approved() OR public.is_staff()));


--
-- Name: event_interests members withdraw their own interest; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members withdraw their own interest" ON public.event_interests;
CREATE POLICY "members withdraw their own interest" ON public.event_interests FOR DELETE USING ((profile_id = auth.uid()));


--
-- Name: ministry_interests members withdraw their own interest; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "members withdraw their own interest" ON public.ministry_interests;
CREATE POLICY "members withdraw their own interest" ON public.ministry_interests FOR DELETE USING ((profile_id = auth.uid()));


--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: ministries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ministries ENABLE ROW LEVEL SECURITY;

--
-- Name: ministry_interests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ministry_interests ENABLE ROW LEVEL SECURITY;

--
-- Name: news_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.news_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_mutes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_mutes ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: enrollments own enrollments visible; staff sees all; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "own enrollments visible; staff sees all" ON public.enrollments;
CREATE POLICY "own enrollments visible; staff sees all" ON public.enrollments FOR SELECT USING (((user_id = auth.uid()) OR public.is_staff()));


--
-- Name: posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: reactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

--
-- Name: discussions read approved discussions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read approved discussions" ON public.discussions;
CREATE POLICY "read approved discussions" ON public.discussions FOR SELECT USING (((status = 'approved'::public.approval_status) OR (author_id = auth.uid()) OR public.is_staff()));


--
-- Name: posts read approved posts; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read approved posts" ON public.posts;
CREATE POLICY "read approved posts" ON public.posts FOR SELECT USING (((status = 'approved'::public.approval_status) OR (author_id = auth.uid()) OR public.is_staff()));


--
-- Name: profiles read basic profile info if approved; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read basic profile info if approved" ON public.profiles;
CREATE POLICY "read basic profile info if approved" ON public.profiles FOR SELECT USING (((id = auth.uid()) OR public.is_staff() OR (public.is_approved() AND (account_status = 'approved'::public.approval_status))));


--
-- Name: comments read comments on approved content; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read comments on approved content" ON public.comments;
CREATE POLICY "read comments on approved content" ON public.comments FOR SELECT USING ((public.is_staff() OR ((entity_type = 'post'::text) AND (EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = comments.entity_id) AND (p.status = 'approved'::public.approval_status))))) OR ((entity_type = 'discussion'::text) AND (EXISTS ( SELECT 1
   FROM public.discussions d
  WHERE ((d.id = comments.entity_id) AND (d.status = 'approved'::public.approval_status)))))));


--
-- Name: ministry_interests read own interest, leaders read theirs; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read own interest, leaders read theirs" ON public.ministry_interests;
CREATE POLICY "read own interest, leaders read theirs" ON public.ministry_interests FOR SELECT USING (((profile_id = auth.uid()) OR public.is_staff() OR (EXISTS ( SELECT 1
   FROM public.ministries m
  WHERE ((m.id = ministry_interests.ministry_id) AND (m.leader_id = auth.uid()))))));


--
-- Name: messages read own messages; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read own messages" ON public.messages;
CREATE POLICY "read own messages" ON public.messages FOR SELECT USING (((sender_id = auth.uid()) OR (recipient_id = auth.uid())));


--
-- Name: notifications read own notifications; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read own notifications" ON public.notifications;
CREATE POLICY "read own notifications" ON public.notifications FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: lesson_completions read own or all-if-staff completions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read own or all-if-staff completions" ON public.lesson_completions;
CREATE POLICY "read own or all-if-staff completions" ON public.lesson_completions FOR SELECT USING ((public.is_staff() OR (EXISTS ( SELECT 1
   FROM public.enrollments e
  WHERE ((e.id = lesson_completions.enrollment_id) AND (e.user_id = auth.uid()))))));


--
-- Name: reactions read reactions on approved content; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "read reactions on approved content" ON public.reactions;
CREATE POLICY "read reactions on approved content" ON public.reactions FOR SELECT USING ((public.is_staff() OR ((entity_type = 'post'::text) AND (EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = reactions.entity_id) AND (p.status = 'approved'::public.approval_status))))) OR ((entity_type = 'discussion'::text) AND (EXISTS ( SELECT 1
   FROM public.discussions d
  WHERE ((d.id = reactions.entity_id) AND (d.status = 'approved'::public.approval_status)))))));


--
-- Name: messages recipient marks read; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "recipient marks read" ON public.messages;
CREATE POLICY "recipient marks read" ON public.messages FOR UPDATE USING ((recipient_id = auth.uid())) WITH CHECK ((recipient_id = auth.uid()));


--
-- Name: reactions remove own reaction; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "remove own reaction" ON public.reactions;
CREATE POLICY "remove own reaction" ON public.reactions FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: site_content; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.site_content ENABLE ROW LEVEL SECURITY;

--
-- Name: site_content site_content_read; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS site_content_read ON public.site_content;
CREATE POLICY site_content_read ON public.site_content FOR SELECT USING (true);


--
-- Name: site_content site_content_write; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS site_content_write ON public.site_content;
CREATE POLICY site_content_write ON public.site_content USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'super_admin'::public.user_role))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'super_admin'::public.user_role)))));


--
-- Name: daily_reminders staff decide reminders; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff decide reminders" ON public.daily_reminders;
CREATE POLICY "staff decide reminders" ON public.daily_reminders FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: discussions staff deletes discussions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff deletes discussions" ON public.discussions;
CREATE POLICY "staff deletes discussions" ON public.discussions FOR DELETE USING ((public.is_staff() OR (author_id = auth.uid())));


--
-- Name: posts staff deletes posts; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff deletes posts" ON public.posts;
CREATE POLICY "staff deletes posts" ON public.posts FOR DELETE USING ((public.is_staff() OR (author_id = auth.uid())));


--
-- Name: events staff manage events; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff manage events" ON public.events;
CREATE POLICY "staff manage events" ON public.events USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: live_series staff manage live series; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff manage live series" ON public.live_series;
CREATE POLICY "staff manage live series" ON public.live_series USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: live_videos staff manage live videos; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff manage live videos" ON public.live_videos;
CREATE POLICY "staff manage live videos" ON public.live_videos USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: discussions staff moderates discussions; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff moderates discussions" ON public.discussions;
CREATE POLICY "staff moderates discussions" ON public.discussions FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: posts staff moderates posts; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff moderates posts" ON public.posts;
CREATE POLICY "staff moderates posts" ON public.posts FOR UPDATE USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: daily_reminders staff review reminders; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "staff review reminders" ON public.daily_reminders;
CREATE POLICY "staff review reminders" ON public.daily_reminders FOR SELECT USING (public.is_staff());


--
-- Name: profiles update own basic info; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "update own basic info" ON public.profiles;
CREATE POLICY "update own basic info" ON public.profiles FOR UPDATE USING ((id = auth.uid())) WITH CHECK (((id = auth.uid()) AND (role = ( SELECT profiles_1.role
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))) AND (account_status = ( SELECT profiles_1.account_status
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))) AND (NOT (leader_id IS DISTINCT FROM ( SELECT profiles_1.leader_id
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))))));


--
-- Name: notifications update own notifications; Type: POLICY; Schema: public; Owner: -
--

DROP POLICY IF EXISTS "update own notifications" ON public.notifications;
CREATE POLICY "update own notifications" ON public.notifications FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- PostgreSQL database dump complete
--

