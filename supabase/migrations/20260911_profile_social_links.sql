-- Social and contact details on member profiles.
--
-- contact_number already existed but was never shown anywhere. These columns
-- make a profile something other members can actually reach, and add an
-- explicit opt-in before a phone number is visible to anyone but staff.

alter table public.profiles
  add column if not exists facebook_url  text,
  add column if not exists instagram_url text,
  -- A phone number is the most sensitive field here, so it stays private until
  -- the member deliberately turns it on. Defaulting this to true would publish
  -- every existing number the moment this migration ran.
  add column if not exists show_contact  boolean not null default false;

-- Store whole URLs, not handles, so the UI never has to guess which network a
-- bare string belongs to. Empty strings are rejected rather than stored as a
-- value that looks present but renders as a broken link.
alter table public.profiles
  drop constraint if exists profiles_facebook_url_check;
alter table public.profiles
  add constraint profiles_facebook_url_check
  check (facebook_url is null or facebook_url ~* '^https://([a-z0-9-]+\.)*facebook\.com/.+');

alter table public.profiles
  drop constraint if exists profiles_instagram_url_check;
alter table public.profiles
  add constraint profiles_instagram_url_check
  check (instagram_url is null or instagram_url ~* '^https://([a-z0-9-]+\.)*instagram\.com/.+');

comment on column public.profiles.facebook_url  is 'Full https URL to the member''s Facebook profile.';
comment on column public.profiles.instagram_url is 'Full https URL to the member''s Instagram profile.';
comment on column public.profiles.show_contact  is 'Member opt-in to showing contact_number to other members.';
