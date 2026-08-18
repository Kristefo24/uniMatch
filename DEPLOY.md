# UniMatch Gasabo — Free Deployment Guide

Host the app so testers can use it and give feedback. Stack:
**Supabase** (database) → **Render** (backend API) → **Netlify** (Flutter Web) or **Firebase App Distribution** (Android APK).

Everything below uses free tiers.

---

## PART 0 — One-time prep

1. Install: Git, Node.js LTS, Flutter SDK, a GitHub account.
2. Your repo is already at `https://github.com/Kristefo24/uniMatch`.
3. Confirm no secrets are tracked (must print nothing):
   ```
   git ls-files | findstr /R "server/.env$"
   ```
   If it prints `server/.env`, remove it first (see PART 5).

---

## PART 1 — Database (Supabase)

1. Go to supabase.com → **New project**. Pick a name + strong DB password + region (choose closest, e.g. EU).
2. Wait for it to provision (~2 min).
3. **Project Settings → Database → Connection string → URI.** Copy it. It looks like:
   ```
   postgresql://postgres:YOUR-PASSWORD@db.xxxx.supabase.co:5432/postgres
   ```
4. Keep this string safe — it's a secret. You'll paste it into Render (PART 2), never into git.

> The server auto-creates all tables and seeds data (admin, universities, criteria) on first run. No manual SQL needed. If you'd rather do it by hand, paste `server/db/schema.sql` into Supabase's SQL Editor.

---

## PART 2 — Backend API (Render)

1. Push `server/` to GitHub (already done if your repo is up).
2. Go to render.com → **New → Web Service** → connect your `uniMatch` repo.
3. Settings:
   - **Root Directory:** `server`
   - **Build Command:** `npm install`
   - **Start Command:** `npm start`
   - **Instance type:** Free
4. **Environment variables** (Add from the Environment tab):
   | Key | Value |
   |-----|-------|
   | `DB_DRIVER` | `supabase` |
   | `DATABASE_URL` | *(the Supabase URI from PART 1)* |
   | `JWT_SECRET` | *(any long random string)* |
   | `PORT` | `4000` |
5. Click **Create Web Service.** Wait for the build → you get a URL like
   `https://unimatch-api.onrender.com`.
6. Test it in a browser:
   ```
   https://unimatch-api.onrender.com/health
   ```
   Should return `{"ok":true,"driver":"supabase"}`.

> Free Render sleeps after ~15 min idle; the first request then takes ~30s to wake. Fine for feedback testing.

> **Render now asks for a card** (identity check only — the free tier still costs $0). If you don't want to add one, use **Koyeb** or **Railway** below instead — same setup, no card.

### PART 2b — Backend on Koyeb (no card) ← use if Render asks for a card
1. Go to koyeb.com → sign up with GitHub (no card required).
2. **Create Web Service → GitHub** → pick your `uniMatch` repo.
3. Settings:
   - **Work directory / Root:** `server`
   - **Build command:** `npm install`
   - **Run command:** `npm start`
   - **Instance:** Free (Nano)
   - **Port:** `4000`
4. Add the same env vars: `DB_DRIVER=supabase`, `DATABASE_URL=…`, `JWT_SECRET=…`, `PORT=4000`.
5. Deploy → you get a URL like `https://unimatch-xxxx.koyeb.app`. Test `…/health`.

### PART 2c — Backend on Railway (no card to start)
1. Go to railway.app → **New Project → Deploy from GitHub repo** → pick `uniMatch`.
2. In the service **Settings**: set **Root Directory** to `server`.
   - Start command is auto-detected as `npm start`; if not, set it.
3. **Variables** tab: add `DB_DRIVER=supabase`, `DATABASE_URL=…`, `JWT_SECRET=…`, `PORT=4000`.
4. **Settings → Networking → Generate Domain** → you get `https://unimatch-production.up.railway.app`. Test `…/health`.

> Railway gives limited free trial credits (enough for testing); Koyeb's Nano service is always-on free. Either avoids a card at signup.

---

## PART 3 — Point the app at the hosted API

1. Open `app/lib/main.dart`.
2. Find the `kBaseUrl` line and set your Render URL as the production base:
   ```dart
   // Use the hosted API for release builds; localhost/10.0.2.2 only for local dev.
   const bool kUseHosted = true;
   final String kBaseUrl = kUseHosted
       ? 'https://unimatch-api.onrender.com'
       : (kIsWeb ? 'http://localhost:4000' : 'http://10.0.2.2:4000');
   ```
3. Save.

---

## PART 4 — Ship the app (pick ONE)

### Option A — Flutter Web on Netlify (one link, any device, no install) ← recommended
1. Build:
   ```
   cd E:\Project\unimatch\app
   flutter build web
   ```
2. Go to netlify.com → **Add new site → Deploy manually.**
3. Drag the folder `app/build/web` onto the upload area.
4. You get a URL like `https://unimatch.netlify.app`. Share it — testers just open it.

CORS is already enabled on the backend (`app.use(cors())`), so the web app can call Render.

### Option B — Android APK via Firebase App Distribution (real app feel)
1. Build:
   ```
   cd E:\Project\unimatch\app
   flutter build apk --release
   ```
   Output: `app/build/app/outputs/flutter-apk/app-release.apk`
2. Go to firebase.google.com → create a project → **App Distribution.**
3. Register an Android app, upload the APK, add testers' emails.
4. Testers get an email link → install directly. No Play Store fee.

### Option C — Send the APK directly (simplest)
1. `flutter build apk --release`
2. Share `app-release.apk` (WhatsApp/Drive). Testers enable "Install from unknown sources," then install.

---

## PART 5 — If GitHub blocks your push (secret detected)

Your `server/.env` must never be committed. Fix:

```
cd E:\Project\unimatch
git rm --cached server/.env
git rm -r --cached app/node_modules server/node_modules
```

Create `.gitignore` in the project root:
```
server/.env
node_modules/
app/node_modules/
server/node_modules/
build/
.dart_tool/
```

Then rewrite history into one clean commit:
```
git add -A
git checkout --orphan clean
git commit -m "UniMatch app + backend (no secrets)"
git branch -D main
git branch -m main
git push -f origin main
```

Verify before pushing (must print nothing):
```
git ls-files | findstr /R "server/.env$"
```

Since the key was exposed, **rotate it**: Supabase → Settings → Database → reset password, and update `DATABASE_URL` in Render only.

---

## PART 6 — Default logins for testers

- **Admin:** `kris@unimatch.com` / `123`
- **A2 graduate / staff:** testers sign up in-app (staff must be confirmed by the admin before they can log in).

---

## Recap

| Layer | Service | Free? | Output |
|-------|---------|-------|--------|
| Database | Supabase | Yes | `DATABASE_URL` |
| Backend | Render | Yes | `https://…onrender.com` |
| App (web) | Netlify | Yes | `https://…netlify.app` |
| App (Android) | Firebase App Distribution | Yes | install link |

Fastest route to feedback: **Supabase + Render + Netlify web** — one URL, works everywhere.
