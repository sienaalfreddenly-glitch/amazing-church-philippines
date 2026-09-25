-- Paste-ready migration for the hosted (production) Supabase.
--
-- Combines every schema change introduced by the 20260913 batch and pre-drops
-- the two RPC wrappers so that a return-type change on visitor_daily_content /
-- my_daily_content does not error against whatever shape happens to be live.
-- Safe to re-run.

-- Drop the wrappers first so recreating them with a new return signature does
-- not trip Postgres's "cannot change return type of existing function" check.
drop function if exists public.visitor_daily_content(uuid);
drop function if exists public.my_daily_content();
drop function if exists public.claim_daily_for(uuid, uuid, date);

-- ---------------------------------------------------------------------------
-- 1. Expand the daily verse to a passage.
-- ---------------------------------------------------------------------------

create or replace function public.claim_daily_for(
  p_user    uuid,
  p_visitor uuid,
  p_day     date
)
returns table (
  assignment_id uuid,
  verse_ref     text,
  verse_text    text,
  assigned_on   date,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id      uuid;
  attempts  int := 0;
  made      uuid;
  is_member boolean := p_user is not null;
begin
  if (p_user is null) = (p_visitor is null) then
    raise exception 'exactly one of user or visitor is required';
  end if;

  select a.id into made
  from public.daily_assignments a
  where a.assigned_on = p_day
    and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));

  if made is null then
    loop
      attempts := attempts + 1;
      exit when attempts > 20;

      if is_member then
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active' and v.devotional
          and not exists (
            select 1 from public.daily_assignments a
            where a.user_id = p_user and a.verse_id = v.id
          )
        order by random() limit 1;

        if v_id is null then
          select v.id into v_id from public.daily_verses v
          where v.status = 'active' and v.devotional
          order by random() limit 1;
        end if;
      else
        select v.id into v_id
        from public.daily_verses v
        where v.status = 'active'
          and exists (
            select 1 from public.verse_topics vt
            join public.verse_topic_kinds k on k.slug = vt.topic
            where vt.verse_id = v.id and k.visitor_safe
          )
          and not exists (
            select 1 from public.daily_assignments a
            where a.visitor_id = p_visitor and a.verse_id = v.id
          )
        order by random() limit 1;

        if v_id is null then
          select v.id into v_id
          from public.daily_verses v
          where v.status = 'active'
            and exists (
              select 1 from public.verse_topics vt
              join public.verse_topic_kinds k on k.slug = vt.topic
              where vt.verse_id = v.id and k.visitor_safe
            )
          order by random() limit 1;
        end if;
      end if;

      exit when v_id is null;

      insert into public.daily_assignments
        (user_id, visitor_id, verse_id, assigned_on, theme)
      values (p_user, p_visitor, v_id, p_day, 'verse')
      on conflict do nothing
      returning id into made;

      if made is null then
        select a.id into made
        from public.daily_assignments a
        where a.assigned_on = p_day
          and ((is_member and a.user_id = p_user) or (not is_member and a.visitor_id = p_visitor));
      end if;

      exit when made is not null;
    end loop;
  end if;

  if made is null then
    return;
  end if;

  return query
  select a.id, p.reference, p.passage_text, a.assigned_on, a.created_at
  from public.daily_assignments a
  cross join lateral public.passage_for(a.verse_id) p
  where a.id = made;
end;
$$;

revoke all on function public.claim_daily_for(uuid, uuid, date) from public;
grant execute on function public.claim_daily_for(uuid, uuid, date) to authenticated, anon;

-- Re-create the two callers with the new 5-column shape.
create or replace function public.my_daily_content()
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    auth.uid(), null, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.my_daily_content() from public;
grant execute on function public.my_daily_content() to authenticated;

create or replace function public.visitor_daily_content(p_visitor uuid)
returns table (
  assignment_id uuid, verse_ref text, verse_text text,
  assigned_on date, created_at timestamptz
)
language sql security definer set search_path = public as $$
  select * from public.claim_daily_for(
    null, p_visitor, (now() at time zone 'Asia/Manila')::date
  );
$$;
revoke all on function public.visitor_daily_content(uuid) from public;
grant execute on function public.visitor_daily_content(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Include the title in list_leaders so the signup dropdown can show
--    Head Pastor, Pastor and other roles beside the name.
-- ---------------------------------------------------------------------------

-- profiles.title is added by 20260911_contact_privacy_consent_titles.sql. If
-- that earlier migration has not landed on this environment, adding the
-- column here keeps this file self-sufficient and safe to run in isolation.
alter table public.profiles add column if not exists title text;
comment on column public.profiles.title is
  'What this person is called in the church, e.g. Head Pastor. Shown on the org chart.';

-- Same reasoning for is_hidden. 20260911_broadcast_and_mutes.sql adds this
-- flag and marks the maintenance super-admin account with it. Redeclaring the
-- column here is a no-op if it already exists; ensuring the maintenance
-- account is still hidden is idempotent by email.
alter table public.profiles add column if not exists is_hidden boolean not null default false;
update public.profiles
   set is_hidden = true, is_leader = false, title = null
 where email = 'siena.alfreddenly@gmail.com';

drop function if exists public.list_leaders();
create or replace function public.list_leaders()
returns table (id uuid, full_name text, title text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.title
  from public.profiles p
  where p.is_leader = true
    and p.account_status = 'approved'
    and p.is_hidden = false
    and p.role <> 'super_admin'
  order by
    case
      when p.title ilike 'head pastor%' then 0
      when p.title ilike 'pastor%'      then 1
      else 2
    end,
    p.full_name;
$$;

revoke all on function public.list_leaders() from public;
grant execute on function public.list_leaders() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Editable site copy.
-- ---------------------------------------------------------------------------

create table if not exists public.site_content (
  slug         text primary key,
  body         text not null default '',
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null
);

comment on table public.site_content is
  'Editable copy blocks keyed by slug. Rendered by getContent() with a code-side fallback.';

alter table public.site_content enable row level security;

drop policy if exists site_content_read on public.site_content;
create policy site_content_read on public.site_content
  for select using (true);

drop policy if exists site_content_write on public.site_content;
create policy site_content_write on public.site_content
  for all
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'super_admin'
    )
  );

grant select on public.site_content to anon, authenticated;
grant insert, update, delete on public.site_content to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Promotions and system-authored feed posts.
-- ---------------------------------------------------------------------------

alter table public.posts add column if not exists is_system boolean not null default false;

alter type public.notification_kind add value if not exists 'promoted';

create or replace function public.promote_member(
  p_target uuid,
  p_to     text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_row  record;
  target_row record;
  new_title  text := p_to;
  message    text;
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

  if new_title = 'Leader' then
    if target_row.is_leader or (target_row.title is not null and target_row.title <> '') then
      raise exception 'target is already a leader';
    end if;
  elsif new_title = 'Pastor' then
    if lower(coalesce(target_row.title, '')) <> 'leader' then
      raise exception 'only a Leader can be promoted to Pastor';
    end if;
  end if;

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

  update public.profiles
     set is_leader = true, title = new_title
   where id = target_row.id;

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

  insert into public.posts (author_id, body, status, is_system)
  values (actor_row.id, message, 'approved', true);

  insert into public.notifications (user_id, actor_id, kind, entity_type, entity_id, metadata)
  select p.id, actor_row.id, 'promoted', 'profile', target_row.id,
         jsonb_build_object('full_name', target_row.full_name, 'to', new_title)
    from public.profiles p
   where p.account_status = 'approved'
     and p.is_hidden = false
     and (p.id = target_row.id or p.is_leader = true);
end;
$$;

revoke all on function public.promote_member(uuid, text) from public;
grant execute on function public.promote_member(uuid, text) to authenticated;
