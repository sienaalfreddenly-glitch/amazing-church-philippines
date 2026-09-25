-- Per-user grant to post and comment as the church.
--
-- Super admins are always allowed. Admins and moderators are refused by
-- default; the super admin flips the flag on individual accounts from the
-- members list or from /admin/church. Ordinary members never see the option.

alter table public.profiles
  add column if not exists can_post_as_church boolean not null default false;

comment on column public.profiles.can_post_as_church is
  'When true and role is admin or moderator, this account may post, comment, and start discussions as Amazing Church Philippines. Super admins bypass this check.';

-- Helper: does this account currently have posting access?
create or replace function public.may_post_as_church(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'super_admin'
        or (role in ('admin', 'moderator') and can_post_as_church)
     from public.profiles where id = p_uid),
    false
  );
$$;

revoke all on function public.may_post_as_church(uuid) from public;
grant execute on function public.may_post_as_church(uuid) to authenticated;

-- Rewrite the two posting RPCs to use the helper.
create or replace function public.post_as_church(
  p_body      text,
  p_title     text default null,
  p_media_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  if not public.may_post_as_church(auth.uid()) then
    raise exception 'not allowed to post as the church';
  end if;
  if p_body is null or trim(p_body) = '' then
    raise exception 'body is required';
  end if;
  insert into public.posts (author_id, body, title, media_url, status, is_system)
  values (public.church_profile_id(), p_body, nullif(p_title, ''), nullif(p_media_url, ''), 'approved', true)
  returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.post_as_church(text, text, text) from public;
grant execute on function public.post_as_church(text, text, text) to authenticated;

create or replace function public.start_discussion_as_church(
  p_title text,
  p_body  text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  if not public.may_post_as_church(auth.uid()) then
    raise exception 'not allowed to post as the church';
  end if;
  if p_title is null or trim(p_title) = '' or p_body is null or trim(p_body) = '' then
    raise exception 'title and body are required';
  end if;
  insert into public.discussions (author_id, title, body, status)
  values (public.church_profile_id(), p_title, p_body, 'approved')
  returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.start_discussion_as_church(text, text) from public;
grant execute on function public.start_discussion_as_church(text, text) to authenticated;

-- Comment as the church. Same authorisation model.
create or replace function public.comment_as_church(
  p_entity_type text,
  p_entity_id   uuid,
  p_body        text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  if not public.may_post_as_church(auth.uid()) then
    raise exception 'not allowed to comment as the church';
  end if;
  if p_body is null or trim(p_body) = '' then
    raise exception 'body is required';
  end if;
  if p_entity_type not in ('post', 'discussion') then
    raise exception 'entity_type must be post or discussion';
  end if;
  insert into public.comments (entity_type, entity_id, author_id, body)
  values (p_entity_type, p_entity_id, public.church_profile_id(), p_body)
  returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.comment_as_church(text, uuid, text) from public;
grant execute on function public.comment_as_church(text, uuid, text) to authenticated;

-- Super admin toggles the flag for another account.
create or replace function public.set_church_posting_access(
  p_user uuid,
  p_can  boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare actor_role text;
begin
  select role into actor_role from public.profiles where id = auth.uid();
  if actor_role is distinct from 'super_admin' then
    raise exception 'only a super admin may grant church posting access';
  end if;
  update public.profiles
     set can_post_as_church = coalesce(p_can, false)
   where id = p_user;
end;
$$;
revoke all on function public.set_church_posting_access(uuid, boolean) from public;
grant execute on function public.set_church_posting_access(uuid, boolean) to authenticated;
