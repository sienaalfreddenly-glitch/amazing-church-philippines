-- Events should reach every member, including the person who created them.
-- The generic broadcast_to_members helper deliberately excludes the author
-- (nobody wants a notification for their own reply), so this trigger writes
-- notifications directly and simply omits the self-check.

create or replace function public.notify_new_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text;
begin
  select full_name into who from public.profiles where id = new.created_by;
  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, new.created_by, 'new_event', 'event', new.id,
         jsonb_build_object('full_name', who, 'title', new.title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false
     and not exists (
       select 1 from public.notification_mutes m
       where m.muter_id = p.id and m.muted_id = new.created_by
     );
  return new;
end $$;
