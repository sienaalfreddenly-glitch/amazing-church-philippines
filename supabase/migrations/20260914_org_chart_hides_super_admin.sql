-- Restore the super-admin and is_hidden filters on org_chart.
--
-- 20260911_contact_privacy_consent_titles.sql recreated the function to
-- return the profile title alongside the row, and in doing so lost the two
-- filters that were on the original. The maintenance super-admin account
-- then reappeared on /org for everyone.

create or replace function public.org_chart()
returns table (
  id uuid,
  full_name text,
  title text,
  avatar_url text,
  leader_id uuid,
  is_leader boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.title, p.avatar_url, p.leader_id, p.is_leader
  from public.profiles p
  where p.account_status = 'approved'
    and p.is_hidden = false
    and p.role <> 'super_admin'
  order by p.is_leader desc, p.full_name;
$$;

revoke all on function public.org_chart() from public;
grant execute on function public.org_chart() to authenticated;
