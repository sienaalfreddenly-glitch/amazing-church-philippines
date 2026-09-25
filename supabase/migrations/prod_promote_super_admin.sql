-- Ensure the maintenance super-admin profile exists on prod and stays hidden.
-- The schema-only bundle does not carry seed data; run this once (safe to
-- re-run) so admin/users lets siena.alfreddenly@gmail.com in and every other
-- view keeps her invisible.
insert into public.profiles (id, full_name, email, role, account_status, is_leader, is_hidden)
select id,
       coalesce(raw_user_meta_data->>'full_name', 'Siena Alfreddenly'),
       email,
       'super_admin',
       'approved',
       false,
       true
from auth.users
where lower(email) = 'siena.alfreddenly@gmail.com'
on conflict (id) do update
  set role                 = 'super_admin',
      account_status       = 'approved',
      is_leader            = false,
      is_hidden            = true,
      title                = null,
      must_change_password = false;
