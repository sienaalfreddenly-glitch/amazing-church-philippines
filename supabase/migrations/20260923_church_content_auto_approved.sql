-- Anything the church authors is approved by default.
--
-- The three insert paths already set status = 'approved' explicitly, but a
-- database-level guard is cheaper than trusting every future caller, and
-- also blocks a moderator from accidentally sending a church post back to
-- pending. Events have no approval field so there is nothing to enforce
-- there.

create or replace function public.enforce_church_auto_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.author_id = public.church_profile_id() then
    new.status := 'approved'::approval_status;
  end if;
  return new;
end;
$$;

drop trigger if exists church_posts_auto_approved on public.posts;
create trigger church_posts_auto_approved
  before insert or update on public.posts
  for each row execute function public.enforce_church_auto_approval();

drop trigger if exists church_discussions_auto_approved on public.discussions;
create trigger church_discussions_auto_approved
  before insert or update on public.discussions
  for each row execute function public.enforce_church_auto_approval();

-- Any existing church posts / discussions that somehow slipped through as
-- pending get promoted now so the guard's coverage is retroactive.
update public.posts       set status = 'approved' where author_id = public.church_profile_id() and status <> 'approved';
update public.discussions set status = 'approved' where author_id = public.church_profile_id() and status <> 'approved';
