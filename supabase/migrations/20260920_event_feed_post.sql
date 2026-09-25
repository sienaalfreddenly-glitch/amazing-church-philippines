-- When an event is created, also post an announcement to the feed authored
-- by the church profile. The existing notify_new_event trigger already fans
-- an ordinary notification out to every member; the feed post is the visual
-- companion so the announcement appears next to every other church post
-- rather than only in the events list.
--
-- notify_new_post is taught to skip these too so members do not receive two
-- notifications for the same event.

create or replace function public.notify_new_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if new.status is distinct from 'approved' then return new; end if;
  if new.system_kind in ('promotion', 'event_announcement') then return new; end if;
  select full_name into who from public.profiles where id = new.author_id;
  perform broadcast_to_members(new.author_id, 'new_post', 'post', new.id,
    jsonb_build_object('full_name', who, 'title', new.title));
  return new;
end $$;

-- Human-friendly Manila time formatter used inside the event announcement body.
create or replace function public.format_event_time(p_when timestamptz)
returns text
language sql
stable
as $$
  select to_char(p_when at time zone 'Asia/Manila', 'FMDay, FMMonth FMDD "at" FMHH12:MI AM');
$$;

create or replace function public.announce_event_in_feed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  church_id uuid := public.church_profile_id();
  body      text;
  location  text := coalesce(nullif(trim(new.location), ''), null);
  when_txt  text := public.format_event_time(new.starts_at);
begin
  body := format(
    'Save the date: %s on %s%s%s',
    new.title,
    when_txt,
    case when location is not null then E' at ' || location else '' end,
    case when new.description is not null and trim(new.description) <> ''
         then E'.\n\n' || trim(new.description)
         else '.' end
  );
  insert into public.posts (author_id, body, title, media_url, status, is_system, system_kind)
  values (
    church_id,
    body,
    'New event: ' || new.title,
    nullif(trim(new.cover_url), ''),
    'approved',
    true,
    'event_announcement'
  );
  return new;
end;
$$;

drop trigger if exists on_new_event_feed on public.events;
create trigger on_new_event_feed
  after insert on public.events
  for each row execute function public.announce_event_in_feed();
