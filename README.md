# Amazing Church Philippines — Community Website

Next.js 14 (App Router) + Supabase. Free-tier friendly.

## What's included

- Home page with Facebook Page embed (posts + auto-appearing live streams)
- Community **Feed** and **Discussions** — every post/thread requires admin/moderator approval
- **Events** page (admin-managed)
- **Live** page (Facebook livestream embed)
- Auth: email + password, **new accounts stay pending until an admin approves**
- Roles: `super_admin`, `admin`, `moderator`, `user`
  - **Super Admin / Admin**: manage users (approve, role change, send password reset, delete), approve/disapprove posts + discussions, delete content
  - **Moderator**: approve/disapprove posts + discussions, delete content
  - **User**: create posts and discussions (all subject to approval)
- Row-Level Security enforces the same rules in the database

## 1. Install prerequisites

Node.js LTS is required. Download & install: <https://nodejs.org/en/download>

After install, open a new PowerShell and verify:
```powershell
node -v
npm -v
```

## 2. Create a free Supabase project

1. Sign up at <https://supabase.com> (free tier is plenty for a church community).
2. Create a new project — remember your database password.
3. Go to **Project Settings → API** and copy:
   - `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`
   - `anon public` key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `service_role` key → `SUPABASE_SERVICE_ROLE_KEY` (keep secret!)
4. Open **SQL Editor**, paste the contents of `supabase/schema.sql`, and run it. This creates tables, roles, RLS policies, and the auto-profile trigger.

## 3. Configure environment variables

In this folder, copy the example file and fill it in:
```powershell
copy .env.local.example .env.local
notepad .env.local
```

## 4. Install & run

```powershell
cd D:\Test\amazing-church
npm install
npm run dev
```

Open <http://localhost:3000>.

## 5. Bootstrap the first Super Admin

1. Sign up at `/signup` with your real email — the account will land pending.
2. In Supabase → SQL Editor, run (replace the email):
   ```sql
   update public.profiles
     set role = 'super_admin', account_status = 'approved'
     where email = 'you@example.com';
   ```
3. Log out and back in. You'll now see the **Admin** link in the nav.

From there, use `/admin/users` to promote others, approve/reject accounts, send password-reset emails, or delete users.

## 6. Deploy to Vercel (free)

1. Push this folder to a GitHub repository.
2. Go to <https://vercel.com>, "Import Project" → select the repo.
3. Add the three environment variables from your `.env.local` in Vercel's **Project Settings → Environment Variables**.
4. Deploy. Every push to `main` re-deploys automatically.
5. In Supabase → **Authentication → URL Configuration**, add your Vercel URL to Site URL and Redirect URLs.

## Facebook embed notes

- The embed uses Facebook's free Page Plugin — no API keys, no expiring tokens.
- Live streams that appear on the page automatically show in the embed timeline; no extra work needed.
- The page URL is configurable in `.env.local` via `NEXT_PUBLIC_FACEBOOK_PAGE_URL`.

## Structure

```
src/
  app/                Next.js App Router pages + API routes
  components/         UI components
  lib/                Supabase clients + role helpers
supabase/schema.sql   Tables, RLS policies, triggers
public/logo.jpg       Church logo
```

## Free-tier limits to know

- **Supabase free**: 500 MB database, 1 GB storage, 50k monthly active users. Plenty for a church community.
- **Vercel Hobby**: 100 GB bandwidth/month. Fine for a church site.
- No credit card required to start on either.
