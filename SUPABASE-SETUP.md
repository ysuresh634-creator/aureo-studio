# Aureo Studio — 3-step secure backend setup (≈2 min)

You do these 3 things; then I build the whole private CRM on it.

## Step 1 — Create the free project
1. Go to **supabase.com** → **Start your project** → sign in with GitHub (fastest, you're already logged in) or email.
2. Click **New project**.
   - **Name:** `aureo-studio`
   - **Database password:** let it generate one, click the copy icon, and paste it somewhere safe (you won't need it day-to-day, but keep it).
   - **Region:** choose the closest — **Mumbai (ap-south-1)** for India, or **Singapore** as backup.
3. Click **Create new project** and wait ~1 minute while it provisions.

## Step 2 — Create the tables + privacy rules (one paste)
1. In the left sidebar click **SQL Editor** → **New query**.
2. Open the file **`supabase-schema.sql`** (in this same folder), copy ALL of it, paste into the editor.
3. Click **Run** (bottom right). You should see “Success. No rows returned.” That's correct — it just built every table and every privacy rule.

## Step 3 — Send me the two keys
1. Left sidebar → **Project Settings** (gear) → **API**.
2. Copy these two values and paste them to me in chat:
   - **Project URL** — looks like `https://xxxxxxxx.supabase.co`
   - **anon public** key — the long one labelled `anon` / `public`
3. That's it — the `anon` key is **safe to share and safe in the browser** (it can do nothing on its own; the database privacy rules from Step 2 control everything). **Never** send me the `service_role` key — keep that one secret.

---

### After you send the two keys, I will:
- Rebuild the CRM to use real Supabase logins (hashed passwords, sessions — no more fake demo logins).
- Create your **team** login and each **client** login (invite-only; no public signup).
- Deploy it privately with `noindex` so it never shows up in Google.
- Give you a one-line snippet to promote yourself to “team” and attach each client to their brand.

Result: a client can only ever see **their own** brand's work — guaranteed by the database, not by hope.
