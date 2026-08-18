# UniMatch Gasabo — Run it in Android Studio

## 1. Start the backend (Terminal 1)

```
cd server
npm install          # first time only
npm start            # → "Server running on port 4000"
```

By default the server uses a local JSON file (`server/data/store.json`) — no database
needed to start. It auto-seeds the 7 Gasabo universities on first run (UoK, EAU, ALU,
AUCA, UR/CMHS, ULK, Kepler College). To use a real database instead, see
**§5 Databases (XAMPP + Supabase)** below.

## 2. Run the app (Android Studio)

1. Open **Android Studio** → *Open* → select `app`.
2. Let it run `flutter pub get` (or Terminal: `cd app && flutter pub get`).
3. Start an emulator: *Device Manager* → create/launch a Pixel device.
4. Press **Run ▶** (or Terminal: `flutter run`).

### Networking
- **Emulator** reaches your PC at `10.0.2.2`. The app is preset to
  `http://10.0.2.2:4000` — no change needed.
- **Physical phone** (same Wi-Fi as your PC): open `lib/main.dart`, change
  `kBaseUrl` to your PC's LAN IP, e.g. `http://192.168.1.20:4000`, and make sure the
  server and phone are on the same network.

## 3. Try the flows

- **Student**: Create account → *A2 graduate* → verify (2-min timer) → Home
  ("Muraho <name>", or "Welcome Amara" if the name is Amara) → pick department →
  programmes → choose criteria → ranked results (real TOPSIS from the server) →
  university detail → **Apply / Shortlist / Rate**.
- **Staff**: Create account → *University staff*. The account is created but you'll
  get "pending confirmation" on login until an admin confirms it.
- **Admin**: There's no admin sign-up UI (by design). Create one directly so you can
  log in and confirm staff — see below.

### Default admin account
There's one built-in admin, seeded automatically — no sign-up needed:

```
email:    kris@unimatch.com
password: 123
```

Log in with the **Admin** tab → you land on the Admin dashboard (staff approvals +
reports). Change this password before shipping. To add more admins, register via the
API while the server is running:

```
curl -X POST http://localhost:4000/signup \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Admin\",\"email\":\"you@unimatch.com\",\"password\":\"...\",\"role\":\"admin\"}"
```

## What's wired vs. stubbed

**Fully working against the backend** (`server/`): signup, login (role-routed, staff
gated on admin confirmation), student department→programme→criteria→**TOPSIS
ranking**→detail, apply, shortlist, rate, admin staff-request confirmation, admin
universities/criteria/students CRUD, and staff campus/combo/criteria editing +
staff/admin reports. Works out of the box on the JSON driver; the same endpoints run
unchanged on MySQL or Supabase.

## 5. Databases (XAMPP local + Supabase online)

The app is designed to run against **two interchangeable databases** that share the
same schema, selected by an environment variable on the server:

- **Local (XAMPP / MySQL)** — for offline development on your PC.
- **Online (Supabase / Postgres)** — for the hosted version others test over the internet.

### A. Local with XAMPP (MySQL)
1. Install **XAMPP**, start **Apache + MySQL** from the control panel.
2. Open `http://localhost/phpmyadmin` → create a database named `unimatch`.
3. Import the schema: phpMyAdmin → `unimatch` → *Import* → choose `server/db/schema.sql`.
4. In `server/.env` set (copy `server/.env.example` → `server/.env` first):
   ```
   DB_DRIVER=mysql
   MYSQL_HOST=127.0.0.1
   MYSQL_PORT=3306
   MYSQL_USER=root
   MYSQL_PASSWORD=
   MYSQL_DATABASE=unimatch
   ```
5. Install the MySQL client and start: `npm install mysql2` then `npm start`.
   The server auto-applies `schema.sql` and seeds the 7 universities on first run.

### B. Online with Supabase (Postgres)
1. Create a free project at supabase.com → note the connection string
   (Project Settings → Database).
2. You can either let the server create the tables automatically on first run, or
   paste `server/db/schema.sql` into the Supabase **SQL Editor** and run it.
3. In `server/.env` set:
   ```
   DB_DRIVER=supabase
   DATABASE_URL=postgresql://postgres:PASSWORD@db.YOUR-PROJECT.supabase.co:5432/postgres
   ```
4. Install the Postgres client: `npm install pg`. Then deploy the server
   (Railway/Render) with the same env vars → the hosted app now reads and writes
   Supabase, so remote testers share one live dataset. (Running `npm start` locally
   with these vars also works.)

### Keeping the two in sync
- Keep **one** `schema.sql` as the single source of truth; apply it to both MySQL and
  Supabase so tables/columns match.
- Switch environments by changing only `DB_DRIVER` — no app code changes.
- Core tables: `users`, `universities`, `campuses`, `campus_departments`,
  `programmes`, `criteria`, `criteria_values`, `staff_data`, `staff_requests`,
  `applications`, `shortlists`, `ratings`.

### Hosting for feedback
- **Backend**: push `server/` to GitHub → deploy on **Railway** or **Render** (free
  tier), set the Supabase env vars there.
- **App for testers**: `flutter build apk` → upload the APK to **Firebase App
  Distribution** and invite testers by email (they install directly, no Play Store).
- Point the app's `kBaseUrl` at your deployed backend URL (https) before building.

## Common issues
- **"Can't reach the server"** in the app → the Node server isn't running, or you're on
  a physical device and `kBaseUrl` still points at `10.0.2.2`.
- **`flutter doctor`** should be all green before you run; fix any ✗ it lists.
- Cleartext HTTP is enabled for local dev via `usesCleartextTraffic="true"`. Remove it
  and use HTTPS before shipping.
