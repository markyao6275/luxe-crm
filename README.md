# Luxe CRM

A multi-brand, multi-store CRM built with:

- **Next.js 15** (App Router, TypeScript) — hosted on Vercel
- **Supabase** — Postgres, Auth, and RLS
- **Vitest** — unit tests

Repository layout:

```
luxe-crm/
├── src/
│   ├── app/                # Next.js App Router pages
│   └── lib/
│       ├── contacts.ts     # Phone/email normalization (dedup keys)
│       └── supabase/       # Browser + server Supabase clients
├── supabase/
│   ├── migrations/         # SQL migrations (schema, RLS, RPCs)
│   ├── seed.sql            # Local seed data
│   └── config.toml         # Local Supabase config
└── .github/workflows/      # CI
```

---

## 1. Run the app locally

**Prereqs:** Node.js 20+, npm 10+, and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started).

```bash
# Install JS dependencies
npm install

# Start local Supabase (Postgres, Auth, Studio) in Docker
supabase start

# Copy envs — supabase start prints the URL and anon key
cp .env.example .env.local
# then edit .env.local with the values printed above

# Start Next.js
npm run dev
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). Supabase Studio is at
[http://127.0.0.1:54323](http://127.0.0.1:54323).

To access the dev server from your phone on the same Wi-Fi, run
`npm run dev -- -H 0.0.0.0` and visit `http://<your-computer-ip>:3000`.

---

## 2. Run tests

```bash
npm test              # one-shot
npm run test:watch    # watch mode
npm run typecheck     # TypeScript only
```

Tests live next to the code they cover (`src/**/*.test.ts`). CI runs
`typecheck` + `test` on every pull request — see
[`.github/workflows/test.yml`](.github/workflows/test.yml).

---

## 3. Deploy to Vercel

1. Push this repo to GitHub.
2. In [Vercel](https://vercel.com), **Add New → Project** and import the repo.
   Framework preset auto-detects as **Next.js**.
3. Under **Environment Variables**, add the values from your Supabase project
   ([Project Settings → API](https://supabase.com/dashboard)):
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY` *(server-only; do **not** prefix with `NEXT_PUBLIC_`)*
4. Click **Deploy**. Subsequent pushes to `main` redeploy automatically; pull
   requests get preview deployments.

> Keep `SUPABASE_SERVICE_ROLE_KEY` out of any `NEXT_PUBLIC_*` variable — it must
> never reach the browser.

---

## 4. Run Supabase migrations

Migrations live in [`supabase/migrations/`](supabase/migrations) and run in
filename order.

### Locally

```bash
supabase start          # if not already running
supabase db reset       # drops local DB, re-applies all migrations, runs seed.sql
```

### Against a hosted project

One-time link:

```bash
supabase login
supabase link --project-ref <your-project-ref>
```

Then push migrations (non-destructive; applies only new ones):

```bash
supabase db push
```

### Creating a new migration

```bash
supabase migration new <short_name>
# edit the generated file in supabase/migrations/
supabase db reset        # verify locally
supabase db push         # apply to linked project
```

> **Never edit a migration that has already been applied to a shared
> environment** — write a follow-up migration instead.

---

## 5. Create users (admin-only for now)

There is no self-signup. Admins provision users via the Supabase admin API or
Studio. A trigger on `auth.users` creates the matching `profiles` row
automatically, reading optional fields from **User Metadata**
(`raw_user_meta_data`).

**Local:** open [http://127.0.0.1:54323](http://127.0.0.1:54323) → Authentication
→ Users → **Add user**. Fill email + password. User Metadata is optional.

### Metadata fields (all optional)

| Key          | Default        | Notes                                               |
|--------------|----------------|-----------------------------------------------------|
| `role`       | `sales_staff`  | `admin` \| `brand_manager` \| `sales_staff`         |
| `brand_id`   | `null`         | UUID of a row in `brands`. Admin must leave unset.  |
| `store_id`   | `null`         | UUID of a row in `stores`. Admin must leave unset.  |
| `first_name` | `null`         |                                                     |
| `last_name`  | `null`         |                                                     |

### Examples

Minimum — no metadata:

```json
{}
```

This creates a profile with `role = sales_staff`, `brand_id = null`. The user
can sign in but RLS will show them nothing until an admin assigns their brand.

A fully-specified sales-staff user:

```json
{
  "role": "sales_staff",
  "brand_id": "<brand uuid>",
  "store_id": "<store uuid>",
  "first_name": "Sam",
  "last_name": "Cruz"
}
```

An admin (brand/store must be unset):

```json
{ "role": "admin", "first_name": "Ops", "last_name": "Admin" }
```

To find UUIDs: Studio → Table Editor → `brands` / `stores`.
