-- Deleting a user failed with "Database error deleting user" because six
-- nullable audit columns referenced profiles with no ON DELETE rule. Keep
-- the content (events, videos, enrollments, ...) and just unlink the person.

alter table public.posts drop constraint if exists posts_moderated_by_fkey;
alter table public.posts add constraint posts_moderated_by_fkey
  foreign key (moderated_by) references public.profiles(id) on delete set null;

alter table public.discussions drop constraint if exists discussions_moderated_by_fkey;
alter table public.discussions add constraint discussions_moderated_by_fkey
  foreign key (moderated_by) references public.profiles(id) on delete set null;

alter table public.events drop constraint if exists events_created_by_fkey;
alter table public.events add constraint events_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete set null;

alter table public.live_videos drop constraint if exists live_videos_created_by_fkey;
alter table public.live_videos add constraint live_videos_created_by_fkey
  foreign key (created_by) references public.profiles(id) on delete set null;

alter table public.enrollments drop constraint if exists enrollments_enrolled_by_fkey;
alter table public.enrollments add constraint enrollments_enrolled_by_fkey
  foreign key (enrolled_by) references public.profiles(id) on delete set null;

alter table public.lesson_completions drop constraint if exists lesson_completions_verified_by_fkey;
alter table public.lesson_completions add constraint lesson_completions_verified_by_fkey
  foreign key (verified_by) references public.profiles(id) on delete set null;
