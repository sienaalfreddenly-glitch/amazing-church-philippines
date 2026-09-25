-- Editable site copy.
--
-- Blocks of text that used to live in JSX are keyed by a stable slug and stored
-- here so super admins can edit them from /admin/content without a deploy.
-- The slug is the contract: code renders getContent('some.slug', fallback), and
-- if the row is missing the hard-coded fallback ships instead. That keeps every
-- page renderable even before an editor has visited the admin panel, and stops
-- a mistyped slug from leaving a blank hole on production.

create table if not exists public.site_content (
  slug         text primary key,
  body         text not null default '',
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null
);

comment on table public.site_content is
  'Editable copy blocks keyed by slug. Rendered by getContent() with a code-side fallback.';

alter table public.site_content enable row level security;

-- Everyone reads: the copy is public.
drop policy if exists site_content_read on public.site_content;
create policy site_content_read on public.site_content
  for select using (true);

-- Only super_admin writes. Admins do not: this is copy that speaks for the
-- church, and the deliberate narrowing keeps that decision with one person.
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
