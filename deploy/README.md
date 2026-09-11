# Self-hosted deployment

The site and Supabase both run on this PC in Docker. Tailscale Funnel gives the
site a public HTTPS address, so anyone can open it without installing anything.

## How the pieces fit

```
public internet
      |
      v
Tailscale Funnel  (terminates TLS, public hostname)
      |
      v
Caddy  127.0.0.1:8091
      |
      +-- /supabase/*  ->  Kong 54321  (Supabase: auth, REST, storage, realtime)
      |
      +-- everything else  ->  app:3000  (Next.js)
```

Supabase is served under a path on the **same** origin as the site rather than
on a second hostname. That keeps auth cookies first-party and means only one
address has to be exposed publicly.

## First-time setup

1. Copy the env file and fill it in:

   ```bash
   cp deploy/.env.example deploy/.env
   ```

   `PUBLIC_ORIGIN` is the Tailscale hostname with no trailing slash. The two
   Supabase keys are the same ones already in `.env.local`.

2. Build and start:

   ```bash
   docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
   ```

3. Point Tailscale Funnel at Caddy:

   ```bash
   tailscale funnel --bg 8091
   ```

4. Check it:

   ```bash
   curl -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8091/
   curl http://127.0.0.1:8091/supabase/auth/v1/health
   ```

## Everyday commands

Restart after a code change:

```bash
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
```

Watch the logs:

```bash
docker compose -f deploy/docker-compose.yml logs -f
```

Stop:

```bash
docker compose -f deploy/docker-compose.yml down
```

## Why the public URL needs a rebuild, not a restart

Next.js inlines every `NEXT_PUBLIC_*` value into the JavaScript the browser
downloads, at build time. Changing `PUBLIC_ORIGIN` therefore requires
`--build`; restarting the container alone will leave the old address baked into
the bundle, and the browser will keep calling the wrong host.

The same applies to `supabase/config.toml`. Its `site_url` is where password
reset and confirmation links point, so it must match the public origin.

## Surviving a reboot

Both containers use `restart: unless-stopped`, so Docker brings them back by
itself. Two things still have to be true:

- **Docker Desktop must start on login.** Settings, General, "Start Docker
  Desktop when you sign in". Without it nothing comes up until you open Docker
  by hand, and the site returns "Failed to fetch" in the meantime.
- **The Supabase containers must be running.** They are a separate compose
  project and are already set to restart automatically.

There is a gap of a minute or two after login while Docker starts. The site is
down during that window.

## Known limits

**The site is only up while this PC is up.** Sleep, reboot, a Windows update,
or losing internet takes the site offline for everyone. That is inherent to
serving from a desktop machine and is the main reason to move to a small
always-on host later.

**Outbound email is not real.** The Supabase stack routes mail to Inbucket, a
local test inbox at <http://127.0.0.1:54324>. Password reset and confirmation
emails land there and never reach members. Sending real mail needs SMTP
credentials configured on the auth container.

**The database is the Supabase CLI's local stack.** It is built for development,
not for holding real member accounts. `supabase stop --no-backup` and
`supabase db reset` both destroy its data, and there is no backup running. Take
a dump before doing anything to that stack:

```bash
docker exec supabase_db_amazing-church pg_dump -U postgres postgres > backup.sql
```

Moving to the official self-hosted Supabase compose, with its own volume, its
own JWT secrets, and a scheduled dump, is the next step before real members
depend on this.
