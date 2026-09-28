-- Deleting a member used to delete everything they ever posted: posts,
-- discussions and comments all cascaded from profiles. That silently wiped the
-- feed and discussions when accounts were cleaned up on 2026-09-25/26.
--
-- Keep the content and detach it instead. author_id becomes null and the UI
-- shows "Former member". Safe to re-run.

begin;

alter table public.posts       alter column author_id drop not null;
alter table public.discussions alter column author_id drop not null;
alter table public.comments    alter column author_id drop not null;

alter table public.posts drop constraint if exists posts_author_id_fkey;
alter table public.posts add constraint posts_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete set null;

alter table public.discussions drop constraint if exists discussions_author_id_fkey;
alter table public.discussions add constraint discussions_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete set null;

alter table public.comments drop constraint if exists comments_author_id_fkey;
alter table public.comments add constraint comments_author_id_fkey
  foreign key (author_id) references public.profiles(id) on delete set null;

commit;
