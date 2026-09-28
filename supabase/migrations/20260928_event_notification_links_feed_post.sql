-- A new-event notification should open the feed at the event's announcement
-- post, but the notification (on_new_event) fires before the post is created
-- (on_new_event_feed; triggers run in name order). After creating the post,
-- stamp its id into that event's notifications so the bell can link to it.
-- Safe to re-run.

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
  post_id   uuid;
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
  )
  returning id into post_id;

  update public.notifications
     set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('post_id', post_id)
   where kind = 'new_event' and entity_type = 'event' and entity_id = new.id;

  return new;
end;
$$;
