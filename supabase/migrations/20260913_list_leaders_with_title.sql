-- Include the title in list_leaders so the signup dropdown can show Head
-- Pastor, Pastor and other roles beside the name. Members can then pick a
-- pastor without having to know which of the listed people is one.
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
    -- Pastors first, then everyone else, then alphabetical inside each band.
    case
      when p.title ilike 'head pastor%' then 0
      when p.title ilike 'pastor%'      then 1
      else 2
    end,
    p.full_name;
$$;

revoke all on function public.list_leaders() from public;
grant execute on function public.list_leaders() to anon, authenticated;
