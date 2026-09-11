-- Ministries are recruitment copy, not member data. The page sits in the public
-- menu, so a visitor deciding whether this church is for them should be able to
-- read what the teams do. Only active ones, and only the description; who is
-- interested and who serves stay behind their own rules.

drop policy if exists "anyone approved can read ministries" on public.ministries;

create policy "anyone can read active ministries"
  on public.ministries for select
  using (is_active = true or is_staff());

grant select on public.ministries to anon;
