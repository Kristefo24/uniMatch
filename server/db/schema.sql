-- UniMatch Gasabo — schema. Kept to a common subset that runs on both
-- MySQL 8 (XAMPP) and PostgreSQL (Supabase). VARCHAR + DOUBLE PRECISION are
-- portable; no engine-specific options. Apply the whole file to either database.

CREATE TABLE IF NOT EXISTS users (
  id             VARCHAR(64) PRIMARY KEY,
  name           VARCHAR(160) NOT NULL,
  email          VARCHAR(160) NOT NULL UNIQUE,
  password       VARCHAR(200) NOT NULL,
  role           VARCHAR(20)  NOT NULL DEFAULT 'student',
  university_id  VARCHAR(64),
  home           VARCHAR(160),
  suspended      INT NOT NULL DEFAULT 0,
  track          VARCHAR(20),
  photo          TEXT,
  reset_otp          VARCHAR(6),
  reset_otp_expires  VARCHAR(40)
);
-- Re-run on every boot so an already-live database picks up the columns too.
ALTER TABLE users ADD COLUMN IF NOT EXISTS track VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_otp VARCHAR(6);
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_otp_expires VARCHAR(40);
ALTER TABLE users ADD COLUMN IF NOT EXISTS home_area VARCHAR(160);
ALTER TABLE users ADD COLUMN IF NOT EXISTS home_lat DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS home_lng DOUBLE PRECISION;

-- Evaluation criteria the admin manages. direction: 'cost' | 'benefit'.
CREATE TABLE IF NOT EXISTS criteria (
  code       VARCHAR(8) PRIMARY KEY,
  label      VARCHAR(200) NOT NULL,
  category   VARCHAR(80),
  direction  VARCHAR(10) NOT NULL DEFAULT 'benefit'
);

-- Admin-managed catalogue of valid A2 subject combinations (e.g. PCB, MPC).
-- subjects is a JSON-encoded array string, e.g. '["Mathematics","Physics","Computer Science"]'.
CREATE TABLE IF NOT EXISTS combinations (
  code      VARCHAR(8) PRIMARY KEY,
  subjects  TEXT NOT NULL
);

-- One JSON blob of a university's staff-entered data (campuses, combos, criteria).
CREATE TABLE IF NOT EXISTS staff_data (
  university_id  VARCHAR(64) PRIMARY KEY,
  data           TEXT
);

CREATE TABLE IF NOT EXISTS universities (
  id    VARCHAR(64) PRIMARY KEY,
  abbr  VARCHAR(40) NOT NULL,
  name  VARCHAR(200) NOT NULL,
  photo TEXT
);
ALTER TABLE universities ADD COLUMN IF NOT EXISTS photo TEXT;

CREATE TABLE IF NOT EXISTS campuses (
  id             VARCHAR(64) PRIMARY KEY,
  university_id  VARCHAR(64) NOT NULL,
  name           VARCHAR(200) NOT NULL
);

CREATE TABLE IF NOT EXISTS campus_departments (
  campus_id   VARCHAR(64) NOT NULL,
  department  VARCHAR(120) NOT NULL
);

CREATE TABLE IF NOT EXISTS programmes (
  id             VARCHAR(64) PRIMARY KEY,
  name           VARCHAR(160) NOT NULL,
  dept           VARCHAR(120) NOT NULL,
  university_id  VARCHAR(64) NOT NULL,
  campus         VARCHAR(200)
);
ALTER TABLE programmes ADD COLUMN IF NOT EXISTS campus VARCHAR(200);

-- One row per (university, criterion). code = C01..C26, value is numeric.
CREATE TABLE IF NOT EXISTS criteria_values (
  university_id  VARCHAR(64) NOT NULL,
  code           VARCHAR(8)  NOT NULL,
  value          DOUBLE PRECISION NOT NULL,
  PRIMARY KEY (university_id, code)
);

CREATE TABLE IF NOT EXISTS staff_requests (
  id             VARCHAR(64) PRIMARY KEY,
  name           VARCHAR(160) NOT NULL,
  email          VARCHAR(160) NOT NULL,
  university_id  VARCHAR(64),
  status         VARCHAR(20) NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS applications (
  id             VARCHAR(64) PRIMARY KEY,
  user_id        VARCHAR(64),
  university_id  VARCHAR(64) NOT NULL,
  programme_id   VARCHAR(64),
  home_area      VARCHAR(160)
);

CREATE TABLE IF NOT EXISTS shortlists (
  id             VARCHAR(64) PRIMARY KEY,
  user_id        VARCHAR(64) NOT NULL,
  university_id  VARCHAR(64) NOT NULL,
  UNIQUE (user_id, university_id)
);

CREATE TABLE IF NOT EXISTS ratings (
  id             VARCHAR(64) PRIMARY KEY,
  user_id        VARCHAR(64) NOT NULL,
  university_id  VARCHAR(64) NOT NULL,
  stars          INT NOT NULL,
  UNIQUE (user_id, university_id)
);

-- One row per criterion code selected in a /rank call — powers the admin
-- "most-chosen criteria" report. user_id is nullable since /rank is public.
CREATE TABLE IF NOT EXISTS criteria_selections (
  id          VARCHAR(64) PRIMARY KEY,
  user_id     VARCHAR(64),
  code        VARCHAR(8)  NOT NULL,
  created_at  VARCHAR(40)
);

-- One row per A2 graduate, holding a full snapshot of the top-5 ranked
-- universities (JSON array of {id, abbr, name, photo, cc, vals, combos} —
-- the same shape /rank returns) from their most recent genuine ranking, plus
-- the criteria that produced it — replaced, not accumulated, on every new
-- ranking. Powers the admin "university popularity" pie chart (by id) and
-- lets a student's "My rankings" page show their last result again after a
-- fresh login/session, without needing to reconstruct dept/programme/home
-- context to re-run TOPSIS.
CREATE TABLE IF NOT EXISTS user_last_ranking (
  user_id         VARCHAR(64) PRIMARY KEY,
  university_ids  TEXT NOT NULL,
  criteria        TEXT,
  updated_at      VARCHAR(40)
);
ALTER TABLE user_last_ranking ADD COLUMN IF NOT EXISTS criteria TEXT;
