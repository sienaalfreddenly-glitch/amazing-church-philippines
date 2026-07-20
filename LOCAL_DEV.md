# Running the whole stack locally with Docker

You can run Postgres, Auth, Storage, Realtime, and the Studio on your own machine — no cloud Supabase project needed. This is exactly what production uses, just in Docker.

## Requirements

- **Docker Desktop** — <https://www.docker.com/products/docker-desktop/> (Windows: WSL2 backend)
- **Node.js 18+** (you already have this)

## First-time setup

```powershell
cd D:\Test\amazing-church

# 1. Start the local Supabase stack — pulls the images the first time (~3 min)
npx supabase start
```

When it finishes it prints something like:
```
API URL: http://127.0.0.1:54321
DB URL:  postgresql://postgres:postgres@127.0.0.1:54322/postgres
Studio URL: http://127.0.0.1:54323
Inbucket URL: http://127.0.0.1:54324
anon key: eyJ....
service_role key: eyJ....
```

Copy those into `.env.local`, replacing your cloud values:

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key from the output>
SUPABASE_SERVICE_ROLE_KEY=<service_role key from the output>
NEXT_PUBLIC_FACEBOOK_PAGE_URL=https://www.facebook.com/amazingchurchphilippines
```

## Apply the schema

Open the local Studio at <http://127.0.0.1:54323> → **SQL Editor** → paste `supabase/schema.sql` → **Run**. Same UX as cloud.

(Alternatively, `npx supabase db reset` re-creates the DB and applies `supabase/seed.sql`, which `\i`-includes `schema.sql`.)

## Sign up your Super Admin

```powershell
node scripts/bootstrap-super-admin.mjs siena.alfreddenly@gmail.com "Siena Alfreddenly"
```

The reset email lands in **Inbucket** at <http://127.0.0.1:54324> (Supabase's built-in local mailbox — no real SMTP needed in dev). Click the link there.

## Day-to-day

```powershell
npx supabase start      # start the stack
npm run dev             # start Next.js
# … work …
npx supabase stop       # stop the containers (keeps data)
```

To wipe the local DB and start fresh: `npx supabase stop --no-backup` then `npx supabase start`.

## Switching between local and cloud

Just swap the three values in `.env.local`. Nothing else in the app changes.

## Common issues

- **"docker daemon not running"** — Start Docker Desktop.
- **Port already in use** — Another Supabase instance is running: `npx supabase stop`, then `npx supabase start`.
- **Storage upload fails locally** — Make sure the `post-media` and `avatars` buckets exist (created by `schema.sql`). Local Studio → Storage.
