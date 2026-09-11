-- Generation without concatenation.
--
-- A template is a finished reminder now, so generating one is choosing a
-- template that has not been used for this verse and storing it. Nothing is
-- joined to anything, which is what guarantees the grammar holds: the text a
-- reader sees is the text somebody wrote and checked.
--
-- The pool is templates multiplied by verses. Thirty templates against 13,239
-- eligible verses is just under 400,000 reminders today, and each template
-- added is another 13,239.

drop function if exists public.generate_reminder_for(uuid);

create or replace function public.generate_reminder_for(p_verse uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  t      record;
  new_id uuid;
  tries  int := 0;
begin
  loop
    tries := tries + 1;
    exit when tries > 6;

    -- A template not yet used for this verse. Every verse can therefore carry
    -- every template exactly once, and never the same words twice.
    select rt.id, rt.text, rt.focus_tag into t
    from public.reminder_templates rt
    where rt.status = 'active'
      and rt.text is not null
      and not exists (
        select 1 from public.daily_reminders r
        where r.verse_id = p_verse and r.template_id = rt.id
      )
    order by random()
    limit 1;

    -- Every template has been used for this verse. The caller moves to another
    -- verse rather than repeating one.
    if not found then
      return null;
    end if;

    begin
      insert into public.daily_reminders (verse_id, reminder, theme, focus_tag, template_id)
      values (p_verse, t.text, t.focus_tag, t.focus_tag, t.id)
      on conflict do nothing
      returning id into new_id;
    exception
      when check_violation or unique_violation then
        -- Another request stored this template for this verse first, or the
        -- similarity guard caught it. Try a different template.
        new_id := null;
    end;

    if new_id is not null then
      return new_id;
    end if;
  end loop;

  return null;
end;
$$;

revoke all on function public.generate_reminder_for(uuid) from public;
grant execute on function public.generate_reminder_for(uuid) to authenticated, anon;

-- The closings existed only to pad a concatenated reminder to length. Nothing
-- composes any more, so they are gone rather than left to confuse the next
-- person reading this schema.
drop table if exists public.reminder_closings;
