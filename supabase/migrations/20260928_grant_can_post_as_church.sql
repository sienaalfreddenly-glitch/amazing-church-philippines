-- 20260919_church_posting_grants.sql added profiles.can_post_as_church but
-- never granted SELECT on it. profiles uses column-level grants, so the
-- composer and comment box, which select this column, got "permission denied"
-- for the whole row and rendered nothing: nobody could post, start a
-- discussion or comment. The flag is not sensitive; members may read it.
grant select (can_post_as_church) on public.profiles to authenticated;
