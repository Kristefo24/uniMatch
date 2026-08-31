// Supabase / Postgres storage driver. Same interface as json-driver.
// Uses the `pg` connection string in DATABASE_URL (works with Supabase's Postgres).
// Requires: npm install pg   (pg ships with @supabase; install directly to be safe).
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const { UNIVERSITIES, buildProgrammes, STAFF_REQUESTS, DEFAULT_ADMIN, CRITERIA, COMBINATIONS, STUDENTS, DEFAULT_PASSWORD_HASH } = require('../seed');

let client;

async function getClient() {
  if (client) return client;
  let pg;
  try { pg = require('pg'); }
  catch { throw new Error('pg not installed. Run: npm install pg'); }
  const { Pool } = pg;
  client = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }, // Supabase requires SSL
  });
  return client;
}

const uid = (p) => `${p}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
// Postgres uses $1,$2… placeholders; helper keeps call sites readable.
const q = async (text, params = []) => (await getClient()).query(text, params);

async function seedIfEmpty() {
  const { rows } = await q('SELECT COUNT(*)::int AS n FROM universities');
  if (rows[0].n > 0) return;
  await q('INSERT INTO users (id,name,email,password,role) VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING',
    ['user-admin', DEFAULT_ADMIN.name, DEFAULT_ADMIN.email, DEFAULT_ADMIN.password, DEFAULT_ADMIN.role]);
  for (const s of (STUDENTS || [])) {
    await q('INSERT INTO users (id,name,email,password,role,home) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING',
      [s.id, s.name, s.email, DEFAULT_PASSWORD_HASH, 'student', s.home]);
  }
  for (const c of (CRITERIA || [])) {
    await q('INSERT INTO criteria (code,label,category,direction) VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING',
      [c.code, c.label, c.category, c.direction]);
  }
  for (const u of UNIVERSITIES) {
    await q('INSERT INTO universities (id,abbr,name) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [u.id, u.abbr, u.name]);
    for (const c of u.campuses) {
      const cid = uid('camp');
      await q('INSERT INTO campuses (id,university_id,name) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [cid, u.id, c.name]);
      for (const d of c.depts) {
        await q('INSERT INTO campus_departments (campus_id,department) VALUES ($1,$2) ON CONFLICT DO NOTHING', [cid, d]);
      }
    }
    for (const [code, value] of Object.entries(u.vals)) {
      await q('INSERT INTO criteria_values (university_id,code,value) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [u.id, code, value]);
    }
  }
  for (const pr of buildProgrammes()) {
    await q('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING',
      [pr.id, pr.name, pr.dept, pr.universityId, pr.campus || null]);
  }
  for (const r of STAFF_REQUESTS) {
    await q('INSERT INTO staff_requests (id,name,email,university_id,status) VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING',
      [r.id, r.name, r.email, r.universityId, r.status]);
  }
}

// Runs on every boot, independent of seedIfEmpty's universities-empty guard —
// an already-live database (universities non-empty) still needs these rows
// backfilled the first time this table exists.
async function seedCombinationsIfMissing() {
  for (const c of COMBINATIONS) {
    await q('INSERT INTO combinations (code,subjects) VALUES ($1,$2) ON CONFLICT (code) DO NOTHING',
      [c.code, JSON.stringify(c.subjects)]);
  }
}

// Runs on every boot — one-time (per row) upgrade of any password still
// stored in plain text (from before hashing was added) to a bcrypt hash.
// Idempotent: a row already hashed is left untouched.
async function migratePlainTextPasswords() {
  const { rows } = await q('SELECT id, password FROM users');
  for (const row of rows) {
    if (/^\$2[aby]\$/.test(row.password || '')) continue;
    const hash = bcrypt.hashSync(row.password, 10);
    await q('UPDATE users SET password=$1 WHERE id=$2', [hash, row.id]);
  }
}

// Defense-in-depth against a programme getting saved twice under the exact
// same name/department/campus (e.g. a client-side re-entry mistake) --
// collapses exact duplicates within one save's payload before it's ever
// persisted, regardless of what caused them. Case-insensitive on name,
// keeps the first occurrence.
function dedupeProgrammes(programmes) {
  const seen = new Set();
  const out = [];
  for (const p of programmes) {
    const key = `${(p.name || '').trim().toLowerCase()}::${p.dept}::${p.campus || ''}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(p);
  }
  return out;
}

// A department with no explicitly-named programme yet shows a synthetic
// placeholder named after the department itself (see listProgrammes) --
// if staff configure eligible combinations while that's showing, they're
// saved under the department's name. When a real named programme later
// replaces the placeholder, carry that data forward to the real name so
// it doesn't go silently unreachable. Copy-only: never deletes the
// original key, so this is safe to call on every save.
function carryForwardOrphanedCombos(oldProgrammes, newProgrammes, oldCombos) {
  const combos = { ...(oldCombos || {}) };
  const oldDeptsWithReal = new Set((oldProgrammes || []).map(p => p.dept));
  const newDeptCounts = {};
  for (const p of newProgrammes) newDeptCounts[p.dept] = (newDeptCounts[p.dept] || 0) + 1;
  for (const p of newProgrammes) {
    if (oldDeptsWithReal.has(p.dept) || newDeptCounts[p.dept] !== 1) continue;
    if (combos[p.dept] && !combos[p.name]) combos[p.name] = combos[p.dept];
  }
  return combos;
}

// One-time (per boot) recovery of combos already orphaned under a stale
// department-name key before the carry-forward above existed. Copy-only,
// idempotent -- a repaired key stops matching once the real name has data.
async function migrateOrphanedComboKeys() {
  const { rows } = await q('SELECT university_id, data FROM staff_data');
  for (const row of rows) {
    let d;
    try { d = JSON.parse(row.data); } catch { continue; }
    if (!d.combos) continue;
    const progs = d.programmes || [];
    const deptCounts = {};
    for (const pr of progs) deptCounts[pr.dept] = (deptCounts[pr.dept] || 0) + 1;
    const byName = new Set(progs.map(pr => pr.name));
    let changed = false;
    for (const dept of Object.keys(d.combos)) {
      if (byName.has(dept) || deptCounts[dept] !== 1) continue;
      const target = progs.find(pr => pr.dept === dept).name;
      if (!d.combos[target]) { d.combos[target] = d.combos[dept]; changed = true; }
    }
    if (changed) await q('UPDATE staff_data SET data=$1 WHERE university_id=$2', [JSON.stringify(d), row.university_id]);
  }
}

async function hydrateUniversity(u) {
  const { rows: camps } = await q('SELECT id,name FROM campuses WHERE university_id=$1', [u.id]);
  for (const c of camps) {
    const { rows: ds } = await q('SELECT department FROM campus_departments WHERE campus_id=$1', [c.id]);
    c.depts = ds.map(x => x.department);
  }
  const { rows: vals } = await q('SELECT code,value FROM criteria_values WHERE university_id=$1', [u.id]);
  const map = {};
  vals.forEach(v => { map[v.code] = Number(v.value); });
  const { rows: rt } = await q('SELECT AVG(stars)::float AS avg, COUNT(*)::int AS n FROM ratings WHERE university_id=$1', [u.id]);
  const { rows: sdRows } = await q('SELECT data FROM staff_data WHERE university_id=$1', [u.id]);
  let sd = { combos: {}, criteria: {} };
  if (sdRows.length) { try { sd = JSON.parse(sdRows[0].data); } catch { /* fallthrough */ } }
  return {
    id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, campuses: camps, vals: map,
    avgRating: rt[0].avg != null ? Number(rt[0].avg.toFixed(2)) : null,
    ratingCount: rt[0].n || 0,
    combos: sd.combos || {},
    religiousBased: !!(sd.criteria && sd.criteria.religiousBased),
    religion: (sd.criteria && sd.criteria.religion) || null,
    schoolLocation: (sd.criteria && sd.criteria.schoolLocation) || null,
    busStops: (sd.criteria && Array.isArray(sd.criteria.busStops)) ? sd.criteria.busStops : [],
    motoStops: (sd.criteria && Array.isArray(sd.criteria.motoStops)) ? sd.criteria.motoStops : [],
    campusPins: (sd.criteria && sd.criteria.campusPins && typeof sd.criteria.campusPins === 'object') ? sd.criteria.campusPins : {},
  };
}

module.exports = {
  async init() {
    const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    await q(schema); // Postgres accepts multiple statements in one query
    await seedIfEmpty();
    await seedCombinationsIfMissing();
    await migratePlainTextPasswords();
    await migrateOrphanedComboKeys();
  },

  async createUser({ name, email, password, role, universityId, track }) {
    const { rows: ex } = await q('SELECT id FROM users WHERE lower(email)=lower($1)', [email]);
    if (ex.length) throw new Error('An account with this email already exists');
    const id = uid('user');
    await q('INSERT INTO users (id,name,email,password,role,university_id,track) VALUES ($1,$2,$3,$4,$5,$6,$7)',
      [id, name, email, password, role, universityId || null, track || null]);
    if (role === 'staff') {
      await q('INSERT INTO staff_requests (id,name,email,university_id,status) VALUES ($1,$2,$3,$4,$5)',
        [uid('req'), name, email, universityId || null, 'pending']);
    }
    return { id, name, email, role, universityId: universityId || null, track: track || null };
  },

  async updateUser(id, { name, track, photo, homeArea, homeLat, homeLng }) {
    // COALESCE: a field omitted from the request body leaves the stored value untouched.
    const { rows } = await q(
      'UPDATE users SET name=COALESCE($1,name), track=COALESCE($2,track), photo=COALESCE($3,photo), ' +
      'home_area=COALESCE($4,home_area), home_lat=COALESCE($5,home_lat), home_lng=COALESCE($6,home_lng) WHERE id=$7 ' +
      'RETURNING id,name,track,photo,home_area,home_lat,home_lng',
      [name || null, track || null, photo || null, homeArea || null, homeLat ?? null, homeLng ?? null, id]);
    return rows[0];
  },

  async setResetOtp(userId, otp, expiresAt) {
    await q('UPDATE users SET reset_otp=$1, reset_otp_expires=$2 WHERE id=$3', [otp, expiresAt, userId]);
    return { ok: true };
  },
  async resetPassword(email, otp, password) {
    const { rows } = await q('SELECT id,reset_otp,reset_otp_expires FROM users WHERE lower(email)=lower($1)', [email]);
    const u = rows[0];
    if (!u || !u.reset_otp || u.reset_otp !== otp) throw new Error('Invalid or expired code');
    if (!u.reset_otp_expires || new Date(u.reset_otp_expires).getTime() < Date.now()) throw new Error('Invalid or expired code');
    await q('UPDATE users SET password=$1, reset_otp=NULL, reset_otp_expires=NULL WHERE id=$2', [password, u.id]);
    return { ok: true };
  },

  async findUserByEmail(email) {
    const { rows } = await q('SELECT * FROM users WHERE lower(email)=lower($1)', [email]);
    const u = rows[0];
    if (u) { u.suspended = !!u.suspended; u.universityId = u.university_id; }
    return u || null;
  },

  async listUniversities() {
    const { rows } = await q('SELECT * FROM universities');
    return Promise.all(rows.map(hydrateUniversity));
  },
  async getUniversity(id) {
    const { rows } = await q('SELECT * FROM universities WHERE id=$1', [id]);
    return rows[0] ? hydrateUniversity(rows[0]) : null;
  },

  async listProgrammes(dept) {
    const { rows } = dept
      ? await q('SELECT * FROM programmes WHERE dept=$1', [dept])
      : await q('SELECT * FROM programmes');
    const real = rows.map(r => ({ id: r.id, name: r.name, dept: r.dept, campus: r.campus || '', years: r.years, universityId: r.university_id }));
    // Scoped by campus too -- a real programme at one campus must not
    // suppress another campus's placeholder for the same department name.
    const covered = new Set(real.map(p => `${p.universityId}::${p.campus}::${p.dept}`));
    const { rows: depts } = dept
      ? await q('SELECT c.university_id, cd.department, c.name AS campus FROM campus_departments cd JOIN campuses c ON c.id=cd.campus_id WHERE cd.department=$1', [dept])
      : await q('SELECT c.university_id, cd.department, c.name AS campus FROM campus_departments cd JOIN campuses c ON c.id=cd.campus_id');
    const synthetic = [];
    for (const row of depts) {
      const key = `${row.university_id}::${row.campus}::${row.department}`;
      if (covered.has(key)) continue;
      covered.add(key);
      synthetic.push({ id: `dept-${row.university_id}-${slug(row.department)}`, name: row.department, dept: row.department, campus: row.campus, years: null, universityId: row.university_id });
    }
    return [...real, ...synthetic];
  },

  async listStaffRequests() {
    const { rows } = await q('SELECT * FROM staff_requests');
    return rows.map(r => ({ id: r.id, name: r.name, email: r.email, universityId: r.university_id, status: r.status }));
  },
  async confirmStaffRequest(id) {
    const { rows } = await q("UPDATE staff_requests SET status='confirmed' WHERE id=$1 RETURNING *", [id]);
    return rows[0];
  },
  async setStaffRequestStatus(id, status) {
    const { rows } = await q('UPDATE staff_requests SET status=$1 WHERE id=$2 RETURNING *', [status, id]);
    const r = rows[0];
    if (r) await q('UPDATE users SET suspended=$1 WHERE lower(email)=lower($2)', [status === 'suspended' ? 1 : 0, r.email]);
    return r;
  },
  async deleteStaffRequest(id) {
    const { rows } = await q('SELECT * FROM staff_requests WHERE id=$1', [id]);
    const r = rows[0];
    await q('DELETE FROM staff_requests WHERE id=$1', [id]);
    if (r) await q("DELETE FROM users WHERE lower(email)=lower($1) AND role='staff'", [r.email]);
    return { ok: true };
  },

  // ---- admin: universities CRUD ----
  async addUniversity({ abbr, name, sector }) {
    const id = uid('uni');
    await q('INSERT INTO universities (id,abbr,name) VALUES ($1,$2,$3)', [id, abbr, name]);
    await q('INSERT INTO campuses (id,university_id,name) VALUES ($1,$2,$3)', [uid('camp'), id, sector || 'Gasabo Campus']);
    return { id, abbr, name, sector };
  },
  async updateUniversity(id, { abbr, name, sector, photo }) {
    if (abbr != null || name != null) {
      await q('UPDATE universities SET abbr=COALESCE($1,abbr), name=COALESCE($2,name) WHERE id=$3', [abbr, name, id]);
    }
    if (photo !== undefined) {
      await q('UPDATE universities SET photo=$1 WHERE id=$2', [photo, id]);
    }
    if (sector != null) {
      const { rows } = await q('SELECT id FROM campuses WHERE university_id=$1 LIMIT 1', [id]);
      if (rows.length) await q('UPDATE campuses SET name=$1 WHERE id=$2', [sector, rows[0].id]);
      else await q('INSERT INTO campuses (id,university_id,name) VALUES ($1,$2,$3)', [uid('camp'), id, sector]);
    }
    return { id, abbr, name, sector, photo };
  },
  async deleteUniversity(id) {
    await q('DELETE FROM universities WHERE id=$1', [id]);
    await q('DELETE FROM campuses WHERE university_id=$1', [id]);
    await q('DELETE FROM criteria_values WHERE university_id=$1', [id]);
    return { ok: true };
  },

  // ---- admin: criteria CRUD ----
  async listCriteria() {
    const { rows } = await q('SELECT code,label,category,direction FROM criteria ORDER BY code');
    return rows;
  },
  async addCriterion({ label, category, direction }) {
    const { rows } = await q('SELECT code FROM criteria');
    const nums = rows.map(r => parseInt((r.code || '').replace(/\D/g, '')) || 0);
    const code = 'C' + String(Math.max(0, ...nums) + 1).padStart(2, '0');
    await q('INSERT INTO criteria (code,label,category,direction) VALUES ($1,$2,$3,$4)',
      [code, label, category || 'General', direction || 'benefit']);
    return { code, label, category, direction };
  },
  async updateCriterion(code, { label, category, direction }) {
    await q('UPDATE criteria SET label=COALESCE($1,label), category=COALESCE($2,category), direction=COALESCE($3,direction) WHERE code=$4',
      [label, category, direction, code]);
    return { code, label, category, direction };
  },
  async deleteCriterion(code) {
    await q('DELETE FROM criteria WHERE code=$1', [code]);
    return { ok: true };
  },

  // ---- admin: subject-combination catalogue CRUD ----
  async listCombinations() {
    const { rows } = await q('SELECT code,subjects FROM combinations ORDER BY code');
    return rows.map(r => ({ code: r.code, subjects: (() => { try { return JSON.parse(r.subjects) || []; } catch { return []; } })() }));
  },
  async addCombination({ code, subjects }) {
    const c = String(code || '').trim().toUpperCase();
    if (!c) throw new Error('Code is required');
    const { rows: existing } = await q('SELECT code FROM combinations WHERE code=$1', [c]);
    if (existing.length) throw new Error('That code already exists');
    await q('INSERT INTO combinations (code,subjects) VALUES ($1,$2)', [c, JSON.stringify(Array.isArray(subjects) ? subjects : [])]);
    return { code: c, subjects: subjects || [] };
  },
  async updateCombination(code, { subjects }) {
    const { rows } = await q('SELECT code FROM combinations WHERE code=$1', [code]);
    if (!rows.length) throw new Error('Combination not found');
    await q('UPDATE combinations SET subjects=$1 WHERE code=$2', [JSON.stringify(Array.isArray(subjects) ? subjects : []), code]);
    return { code, subjects: subjects || [] };
  },
  async deleteCombination(code) {
    await q('DELETE FROM combinations WHERE code=$1', [code]);
    // Cascade: every university's staff-set eligibility (programme -> code ->
    // subjects) loses this code too, so nothing references a combination
    // that no longer exists in the catalogue.
    const { rows } = await q('SELECT university_id, data FROM staff_data');
    for (const row of rows) {
      let sd;
      try { sd = JSON.parse(row.data); } catch { continue; }
      if (!sd || !sd.combos || typeof sd.combos !== 'object') continue;
      let changed = false;
      for (const programme of Object.keys(sd.combos)) {
        if (sd.combos[programme] && typeof sd.combos[programme] === 'object' && code in sd.combos[programme]) {
          delete sd.combos[programme][code];
          changed = true;
        }
      }
      if (changed) await q('UPDATE staff_data SET data=$1 WHERE university_id=$2', [JSON.stringify(sd), row.university_id]);
    }
    return { ok: true };
  },

  // ---- admin: students ----
  async listStudents() {
    const { rows } = await q("SELECT id,name,email,home,suspended FROM users WHERE role='student'");
    return rows.map(u => ({ id: u.id, name: u.name, email: u.email, home: u.home || '', suspended: !!u.suspended }));
  },
  async setStudentSuspended(id, suspended) {
    await q('UPDATE users SET suspended=$1 WHERE id=$2', [suspended ? 1 : 0, id]);
    return { id, suspended: !!suspended };
  },
  async deleteStudent(id) {
    await q("DELETE FROM users WHERE id=$1 AND role='student'", [id]);
    return { ok: true };
  },

  // ---- staff: own university data ----
  async _staffData(uniId) {
    const { rows } = await q('SELECT data FROM staff_data WHERE university_id=$1', [uniId]);
    if (rows.length) { try { return JSON.parse(rows[0].data); } catch { /* fallthrough */ } }
    return { campuses: [], combos: {}, criteria: {} };
  },
  async _saveStaffData(uniId, data) {
    await q('INSERT INTO staff_data (university_id,data) VALUES ($1,$2) ON CONFLICT (university_id) DO UPDATE SET data=EXCLUDED.data',
      [uniId, JSON.stringify(data)]);
  },
  async getStaffData(uniId) { return this._staffData(uniId); },
  async saveStaffCampuses(uniId, campuses) {
    const d = await this._staffData(uniId); d.campuses = campuses;
    await this._saveStaffData(uniId, d);
    await q('DELETE FROM campuses WHERE university_id=$1', [uniId]);
    for (const c of campuses) {
      const cid = uid('camp');
      await q('INSERT INTO campuses (id,university_id,name) VALUES ($1,$2,$3)', [cid, uniId, c.name]);
      for (const dep of (c.depts || [])) {
        await q('INSERT INTO campus_departments (campus_id,department) VALUES ($1,$2)', [cid, dep]);
      }
    }
    return d;
  },
  // Saves campuses and programmes together in one transaction so they can
  // never desync from a partial failure the way two independent HTTP
  // requests could (e.g. a deleted campus's programmes surviving because
  // only the campuses save reached the server before a network hiccup) —
  // either both replace-writes land, or neither does.
  async saveStaffCampusesAndProgrammes(uniId, campuses, programmes) {
    const pool = await getClient();
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query('SELECT data FROM staff_data WHERE university_id=$1', [uniId]);
      let d = { campuses: [], combos: {}, criteria: {} };
      if (rows.length) { try { d = JSON.parse(rows[0].data); } catch { /* fallthrough */ } }
      d.campuses = campuses;
      d.programmes = programmes;
      await client.query(
        'INSERT INTO staff_data (university_id,data) VALUES ($1,$2) ON CONFLICT (university_id) DO UPDATE SET data=EXCLUDED.data',
        [uniId, JSON.stringify(d)]);
      await client.query('DELETE FROM campuses WHERE university_id=$1', [uniId]);
      for (const c of campuses) {
        const cid = uid('camp');
        await client.query('INSERT INTO campuses (id,university_id,name) VALUES ($1,$2,$3)', [cid, uniId, c.name]);
        for (const dep of (c.depts || [])) {
          await client.query('INSERT INTO campus_departments (campus_id,department) VALUES ($1,$2)', [cid, dep]);
        }
      }
      await client.query('DELETE FROM programmes WHERE university_id=$1', [uniId]);
      for (const pr of programmes) {
        await client.query('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES ($1,$2,$3,$4,$5)',
          [uid('prog'), pr.name, pr.dept, uniId, pr.campus || null]);
      }
      await client.query('COMMIT');
      return d;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  },
  async saveStaffCombos(uniId, combos) {
    const d = await this._staffData(uniId); d.combos = combos;
    await this._saveStaffData(uniId, d); return d;
  },
  async saveStaffProgrammes(uniId, programmes) {
    programmes = dedupeProgrammes(programmes);
    const d = await this._staffData(uniId);
    d.combos = carryForwardOrphanedCombos(d.programmes, programmes, d.combos);
    d.programmes = programmes;
    await this._saveStaffData(uniId, d);
    await q('DELETE FROM programmes WHERE university_id=$1', [uniId]);
    for (const pr of programmes) {
      await q('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES ($1,$2,$3,$4,$5)',
        [uid('prog'), pr.name, pr.dept, uniId, pr.campus || null]);
    }
    return d;
  },
  // Renames a programme by name wherever it's referenced -- its row(s) in
  // the flat programmes table/blob, AND its combos entry -- so the two can
  // never drift apart the way a plain combos-key edit would (which would
  // just re-orphan the entry the moment it no longer matches the real name).
  // Works equally for a genuinely orphaned combos-only entry (no matching
  // programme row exists) -- the combos key still moves, nothing else to do.
  async renameStaffProgramme(uniId, oldName, newName) {
    const d = await this._staffData(uniId);
    if (oldName !== newName && d.combos && d.combos[oldName] !== undefined && d.combos[newName] !== undefined) {
      throw new Error(`"${newName}" already has its own combinations set — rename or delete one first`);
    }
    d.programmes = (d.programmes || []).map(pr => pr.name === oldName ? { ...pr, name: newName } : pr);
    const combos = { ...(d.combos || {}) };
    if (oldName !== newName && combos[oldName] !== undefined) {
      combos[newName] = combos[oldName];
      delete combos[oldName];
    }
    d.combos = combos;
    await this._saveStaffData(uniId, d);
    await q('UPDATE programmes SET name=$1 WHERE university_id=$2 AND name=$3', [newName, uniId, oldName]);
    return d;
  },
  // Removes a programme by name everywhere it's referenced -- its row(s) in
  // the flat programmes table/blob, AND its combos entry -- not just its
  // combinations. Handles a purely orphaned combos-only entry the same way:
  // no programme row matches, so that part is a no-op, only the combos key
  // is dropped.
  async deleteStaffProgramme(uniId, name) {
    const d = await this._staffData(uniId);
    d.programmes = (d.programmes || []).filter(pr => pr.name !== name);
    const combos = { ...(d.combos || {}) };
    delete combos[name];
    d.combos = combos;
    await this._saveStaffData(uniId, d);
    await q('DELETE FROM programmes WHERE university_id=$1 AND name=$2', [uniId, name]);
    return d;
  },
  async saveStaffCriteria(uniId, criteria) {
    const d = await this._staffData(uniId); d.criteria = criteria;
    await this._saveStaffData(uniId, d);
    const keep = new Set(Object.keys(criteria).filter(k => /^C\d+$/.test(k) && typeof criteria[k] === 'number'));
    // Clear any previously-stored Cxx value whose code dropped out of this
    // save (e.g. staff removed all bus/moto stops -> C09 must not linger).
    const { rows: existing } = await q('SELECT code FROM criteria_values WHERE university_id=$1', [uniId]);
    for (const row of existing) {
      if (/^C\d+$/.test(row.code) && !keep.has(row.code)) {
        await q('DELETE FROM criteria_values WHERE university_id=$1 AND code=$2', [uniId, row.code]);
      }
    }
    for (const [code, value] of Object.entries(criteria)) {
      if (typeof value !== 'number' || !/^C\d+$/.test(code)) continue;
      await q('INSERT INTO criteria_values (university_id,code,value) VALUES ($1,$2,$3) ON CONFLICT (university_id,code) DO UPDATE SET value=EXCLUDED.value',
        [uniId, code, value]);
    }
    return d;
  },
  async staffReport(uniId) {
    const { rows: apps } = await q(
      'SELECT a.home_area, a.created_at, u.name, u.email FROM applications a LEFT JOIN users u ON u.id=a.user_id WHERE a.university_id=$1', [uniId]);
    const { rows: sl } = await q('SELECT COUNT(*)::int AS n FROM shortlists WHERE university_id=$1', [uniId]);
    const { rows: rt } = await q('SELECT AVG(stars)::float AS avg, COUNT(*)::int AS n FROM ratings WHERE university_id=$1', [uniId]);
    // How many students currently have this university in their latest
    // ranked top-5 -- same source/shape as universityPopularity(), scoped
    // to one university instead of tallying every one.
    const { rows: lr } = await q('SELECT university_ids FROM user_last_ranking');
    const rankedListCount = lr.filter(r => {
      try { return JSON.parse(r.university_ids || '[]').some(u => u.id === uniId); } catch { return false; }
    }).length;
    const applicants = apps.map(a => ({
      name: a.name || 'A2 graduate', email: a.email || '', home: a.home_area || '',
      date: a.created_at ? new Date(a.created_at).toISOString().slice(0, 10) : '',
    }));
    const byHome = {};
    applicants.forEach(a => { const h = a.home || 'Unknown'; byHome[h] = (byHome[h] || 0) + 1; });
    // Week-over-week application growth. Legacy applications predating the
    // created_at column are NULL -- they still count toward applyCount but
    // can't be placed in either window, so they're excluded from both
    // rather than guessed into one and skewing the very first reading.
    const now = Date.now();
    const day = 24 * 60 * 60 * 1000;
    let applyLast7 = 0, applyPrev7 = 0;
    for (const a of apps) {
      if (!a.created_at) continue;
      const age = now - new Date(a.created_at).getTime();
      if (age >= 0 && age < 7 * day) applyLast7++;
      else if (age >= 7 * day && age < 14 * day) applyPrev7++;
    }
    return {
      appearedCount: (sl[0].n || 0) + apps.length,
      shortlistCount: sl[0].n || 0,
      applyCount: apps.length,
      applicants,
      homeAreas: Object.entries(byHome).map(([home, count]) => ({ home, count })).sort((a, b) => b.count - a.count),
      avgRating: rt[0].avg != null ? Number(rt[0].avg.toFixed(2)) : null,
      ratingCount: rt[0].n || 0,
      rankedListCount,
      applyLast7,
      applyPrev7,
    };
  },
  async adminReport() {
    const { rows: unis } = await q('SELECT id,abbr,name FROM universities');
    const { rows: applyRows } = await q('SELECT university_id, COUNT(*)::int AS n FROM applications GROUP BY university_id');
    const { rows: slRows } = await q('SELECT university_id, COUNT(*)::int AS n FROM shortlists GROUP BY university_id');
    const applyBy = Object.fromEntries(applyRows.map(r => [r.university_id, r.n]));
    const slBy = Object.fromEntries(slRows.map(r => [r.university_id, r.n]));
    const { rows: apps } = await q(
      'SELECT a.home_area, a.university_id, a.created_at, u.name, u.email FROM applications a LEFT JOIN users u ON u.id=a.user_id');
    const { rows: students } = await q("SELECT name,email,home,home_area,suspended FROM users WHERE role='student'");
    const { rows: staff } = await q('SELECT name,email,status FROM staff_requests');
    const { rows: rt } = await q('SELECT AVG(stars)::float AS avg FROM ratings');
    const uName = Object.fromEntries(unis.map(u => [u.id, u.name]));
    return {
      universities: unis.map(u => ({ abbr: u.abbr, name: u.name, applications: applyBy[u.id] || 0, shortlists: slBy[u.id] || 0 })),
      applications: apps.map(a => ({ student: a.name || 'A2 graduate', email: a.email || '', university: uName[a.university_id] || a.university_id, home: a.home_area || '',
          date: a.created_at ? new Date(a.created_at).toISOString().slice(0, 10) : '' })),
      students: students.map(s => ({ name: s.name, email: s.email, home: s.home_area || s.home || '', suspended: !!s.suspended })),
      staff: staff.map(s => ({ name: s.name, email: s.email, status: s.status })),
      avgRating: rt[0].avg != null ? Number(rt[0].avg.toFixed(2)) : null,
    };
  },

  async recordApplication({ userId, universityId, programmeId, homeArea }) {
    const id = uid('app');
    await q('INSERT INTO applications (id,user_id,university_id,programme_id,home_area,created_at) VALUES ($1,$2,$3,$4,$5,NOW())',
      [id, userId, universityId, programmeId, homeArea]);
    return { id };
  },
  async recordShortlist({ userId, universityId }) {
    await q('INSERT INTO shortlists (id,user_id,university_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',
      [uid('sl'), userId, universityId]);
    return { ok: true };
  },
  async listShortlist(userId) {
    const { rows } = await q(
      'SELECT u.id,u.abbr,u.name,u.photo FROM shortlists s JOIN universities u ON u.id=s.university_id WHERE s.user_id=$1',
      [userId]);
    return rows;
  },
  async removeShortlist(userId, universityId) {
    await q('DELETE FROM shortlists WHERE user_id=$1 AND university_id=$2', [userId, universityId]);
    return { ok: true };
  },
  async recordRating({ userId, universityId, stars }) {
    // A university with no criteria answers on file has nothing genuine
    // behind a star rating -- it can still show up in rankings (scored 0),
    // but graduates can't rate it. Mirrors the same check in json/mysql.
    const { rows: cv } = await q('SELECT 1 FROM criteria_values WHERE university_id=$1 LIMIT 1', [universityId]);
    if (!cv.length) { const e = new Error('This university has not set up its criteria answers yet.'); e.status = 400; throw e; }
    await q(
      'INSERT INTO ratings (id,user_id,university_id,stars) VALUES ($1,$2,$3,$4) ' +
      'ON CONFLICT (user_id,university_id) DO UPDATE SET stars=EXCLUDED.stars',
      [uid('rt'), userId, universityId, stars]);
    return { ok: true };
  },
  async myRating({ userId, universityId }) {
    const { rows } = await q('SELECT stars FROM ratings WHERE user_id=$1 AND university_id=$2', [userId, universityId]);
    return { stars: rows[0] ? rows[0].stars : null };
  },

  async recordCriteriaSelections(userId, codes) {
    for (const code of codes) {
      await q('INSERT INTO criteria_selections (id,user_id,code,created_at) VALUES ($1,$2,$3,$4)',
        [uid('csel'), userId || null, code, new Date().toISOString()]);
    }
    return { ok: true };
  },
  async criteriaUsageCounts(universityId) {
    if (!universityId) {
      const { rows } = await q(
        'SELECT cs.code, c.label, COUNT(*)::int AS count FROM criteria_selections cs ' +
        'LEFT JOIN criteria c ON c.code = cs.code GROUP BY cs.code, c.label ORDER BY count DESC');
      return rows.map(r => ({ code: r.code, label: r.label || r.code, count: r.count }));
    }
    // criteria_selections isn't tied to a university (a student weighs
    // criteria once, then ranks everyone with them) -- so a per-university
    // breakdown is derived from user_last_ranking instead: for every
    // student whose latest ranking actually included this university,
    // tally the criteria codes that ranking was run with.
    const { rows } = await q('SELECT university_ids, criteria FROM user_last_ranking');
    const { rows: labelRows } = await q('SELECT code, label FROM criteria');
    const labelByCode = Object.fromEntries(labelRows.map(r => [r.code, r.label]));
    const counts = {};
    for (const row of rows) {
      let unis = [], crit = [];
      try { unis = JSON.parse(row.university_ids || '[]'); } catch { /* ignore malformed row */ }
      try { crit = JSON.parse(row.criteria || '[]'); } catch { /* ignore malformed row */ }
      if (!unis.some(u => u.id === universityId)) continue;
      for (const c of crit) {
        const code = c && c.code;
        if (!code) continue;
        counts[code] = (counts[code] || 0) + 1;
      }
    }
    return Object.entries(counts).map(([code, count]) => ({ code, label: labelByCode[code] || code, count }));
  },

  async saveUserLastRanking(userId, ranked, criteria) {
    await q(
      'INSERT INTO user_last_ranking (user_id,university_ids,criteria,updated_at) VALUES ($1,$2,$3,$4) ' +
      'ON CONFLICT (user_id) DO UPDATE SET university_ids=EXCLUDED.university_ids, criteria=EXCLUDED.criteria, updated_at=EXCLUDED.updated_at',
      [userId, JSON.stringify(ranked), JSON.stringify(criteria || []), new Date().toISOString()]);
    return { ok: true };
  },
  async getUserLastRanking(userId) {
    const { rows } = await q('SELECT university_ids, criteria, updated_at FROM user_last_ranking WHERE user_id=$1', [userId]);
    if (!rows.length) return null;
    let ranked = [], criteria = [];
    try { ranked = JSON.parse(rows[0].university_ids) || []; } catch { /* ignore malformed row */ }
    try { criteria = JSON.parse(rows[0].criteria) || []; } catch { /* ignore malformed row */ }
    return { ranked, criteria, updatedAt: rows[0].updated_at };
  },
  async universityPopularity() {
    const { rows } = await q('SELECT university_ids FROM user_last_ranking');
    const counts = {};
    for (const row of rows) {
      let ranked = [];
      try { ranked = JSON.parse(row.university_ids) || []; } catch { /* ignore malformed row */ }
      for (const u of ranked) counts[u.id] = (counts[u.id] || 0) + 1;
    }
    // Denominator is every registered A2 graduate, not just those who've
    // ranked at least once — e.g. "22% of all 30 graduate accounts".
    const totalStudents = (await this.listStudents()).length;
    const unis = await this.listUniversities();
    return {
      totalStudents,
      universities: unis.map(u => ({
        id: u.id, abbr: u.abbr, name: u.name,
        count: counts[u.id] || 0,
        pct: totalStudents ? Number(((counts[u.id] || 0) / totalStudents * 100).toFixed(1)) : 0,
      })),
    };
  },
};
