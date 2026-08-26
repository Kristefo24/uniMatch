// MySQL storage driver (XAMPP / local MySQL). Same interface as json-driver.
// Requires: npm install mysql2   and a `unimatch` database created from schema.sql.
const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');
const { UNIVERSITIES, buildProgrammes, STAFF_REQUESTS, DEFAULT_ADMIN, CRITERIA, COMBINATIONS, STUDENTS, DEFAULT_PASSWORD_HASH } = require('../seed');

let pool;

async function getPool() {
  if (pool) return pool;
  let mysql;
  try { mysql = require('mysql2/promise'); }
  catch { throw new Error('mysql2 not installed. Run: npm install mysql2'); }
  pool = mysql.createPool({
    host: process.env.MYSQL_HOST || '127.0.0.1',
    port: Number(process.env.MYSQL_PORT || 3306),
    user: process.env.MYSQL_USER || 'root',
    password: process.env.MYSQL_PASSWORD || '',
    database: process.env.MYSQL_DATABASE || 'unimatch',
    waitForConnections: true,
    connectionLimit: 10,
  });
  return pool;
}

const uid = (p) => `${p}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

async function seedIfEmpty() {
  const p = await getPool();
  const [rows] = await p.query('SELECT COUNT(*) AS n FROM universities');
  if (rows[0].n > 0) return;
  // admin
  await p.query('INSERT INTO users (id,name,email,password,role) VALUES (?,?,?,?,?)',
    ['user-admin', DEFAULT_ADMIN.name, DEFAULT_ADMIN.email, DEFAULT_ADMIN.password, DEFAULT_ADMIN.role]);
  // seeded students
  for (const s of (STUDENTS || [])) {
    await p.query('INSERT INTO users (id,name,email,password,role,home) VALUES (?,?,?,?,?,?)',
      [s.id, s.name, s.email, DEFAULT_PASSWORD_HASH, 'student', s.home]);
  }
  // evaluation criteria
  for (const c of (CRITERIA || [])) {
    await p.query('INSERT INTO criteria (code,label,category,direction) VALUES (?,?,?,?)',
      [c.code, c.label, c.category, c.direction]);
  }
  // universities + campuses + criteria_values
  for (const u of UNIVERSITIES) {
    await p.query('INSERT INTO universities (id,abbr,name) VALUES (?,?,?)', [u.id, u.abbr, u.name]);
    for (const c of u.campuses) {
      const cid = uid('camp');
      await p.query('INSERT INTO campuses (id,university_id,name) VALUES (?,?,?)', [cid, u.id, c.name]);
      for (const d of c.depts) {
        await p.query('INSERT INTO campus_departments (campus_id,department) VALUES (?,?)', [cid, d]);
      }
    }
    for (const [code, value] of Object.entries(u.vals)) {
      await p.query('INSERT INTO criteria_values (university_id,code,value) VALUES (?,?,?)', [u.id, code, value]);
    }
  }
  for (const pr of buildProgrammes()) {
    await p.query('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES (?,?,?,?,?)',
      [pr.id, pr.name, pr.dept, pr.universityId, pr.campus || null]);
  }
  for (const r of STAFF_REQUESTS) {
    await p.query('INSERT INTO staff_requests (id,name,email,university_id,status) VALUES (?,?,?,?,?)',
      [r.id, r.name, r.email, r.universityId, r.status]);
  }
}

// Runs on every boot, independent of seedIfEmpty's universities-empty guard —
// an already-live database (universities non-empty) still needs these rows
// backfilled the first time this table exists.
async function seedCombinationsIfMissing() {
  const p = await getPool();
  for (const c of COMBINATIONS) {
    await p.query('INSERT IGNORE INTO combinations (code,subjects) VALUES (?,?)', [c.code, JSON.stringify(c.subjects)]);
  }
}

// Runs on every boot — one-time (per row) upgrade of any password still
// stored in plain text (from before hashing was added) to a bcrypt hash.
// Idempotent: a row already hashed is left untouched.
async function migratePlainTextPasswords() {
  const p = await getPool();
  const [rows] = await p.query('SELECT id, password FROM users');
  for (const row of rows) {
    if (/^\$2[aby]\$/.test(row.password || '')) continue;
    const hash = bcrypt.hashSync(row.password, 10);
    await p.query('UPDATE users SET password=? WHERE id=?', [hash, row.id]);
  }
}

async function hydrateUniversity(u) {
  const p = await getPool();
  const [camps] = await p.query('SELECT id,name FROM campuses WHERE university_id=?', [u.id]);
  for (const c of camps) {
    const [ds] = await p.query('SELECT department FROM campus_departments WHERE campus_id=?', [c.id]);
    c.depts = ds.map(x => x.department);
  }
  const [vals] = await p.query('SELECT code,value FROM criteria_values WHERE university_id=?', [u.id]);
  const map = {};
  vals.forEach(v => { map[v.code] = Number(v.value); });
  const [[rt]] = await p.query('SELECT AVG(stars) AS avg, COUNT(*) AS n FROM ratings WHERE university_id=?', [u.id]);
  const [sdRows] = await p.query('SELECT data FROM staff_data WHERE university_id=?', [u.id]);
  let sd = { combos: {}, criteria: {} };
  if (sdRows.length) { try { sd = JSON.parse(sdRows[0].data); } catch { /* fallthrough */ } }
  return {
    id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, campuses: camps, vals: map,
    avgRating: rt.avg != null ? Number(Number(rt.avg).toFixed(2)) : null,
    ratingCount: rt.n || 0,
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
    // Auto-apply schema so `npm start` works after just creating the empty DB.
    const p = await getPool();
    const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    for (const stmt of schema.split(';').map(s => s.trim()).filter(Boolean)) {
      await p.query(stmt);
    }
    await seedIfEmpty();
    await seedCombinationsIfMissing();
    await migratePlainTextPasswords();
  },

  async createUser({ name, email, password, role, universityId, track }) {
    const p = await getPool();
    const [ex] = await p.query('SELECT id FROM users WHERE email=?', [email]);
    if (ex.length) throw new Error('An account with this email already exists');
    const id = uid('user');
    await p.query('INSERT INTO users (id,name,email,password,role,university_id,track) VALUES (?,?,?,?,?,?,?)',
      [id, name, email, password, role, universityId || null, track || null]);
    if (role === 'staff') {
      await p.query('INSERT INTO staff_requests (id,name,email,university_id,status) VALUES (?,?,?,?,?)',
        [uid('req'), name, email, universityId || null, 'pending']);
    }
    return { id, name, email, role, universityId: universityId || null, track: track || null };
  },

  async updateUser(id, { name, track, photo }) {
    const p = await getPool();
    // COALESCE: a field omitted from the request body leaves the stored value untouched.
    await p.query('UPDATE users SET name=COALESCE(?,name), track=COALESCE(?,track), photo=COALESCE(?,photo) WHERE id=?',
      [name || null, track || null, photo || null, id]);
    const [rows] = await p.query('SELECT id,name,track,photo FROM users WHERE id=?', [id]);
    return rows[0];
  },

  async setResetOtp(userId, otp, expiresAt) {
    const p = await getPool();
    await p.query('UPDATE users SET reset_otp=?, reset_otp_expires=? WHERE id=?', [otp, expiresAt, userId]);
    return { ok: true };
  },
  async resetPassword(email, otp, password) {
    const p = await getPool();
    const [rows] = await p.query('SELECT id,reset_otp,reset_otp_expires FROM users WHERE email=?', [email]);
    const u = rows[0];
    if (!u || !u.reset_otp || u.reset_otp !== otp) throw new Error('Invalid or expired code');
    if (!u.reset_otp_expires || new Date(u.reset_otp_expires).getTime() < Date.now()) throw new Error('Invalid or expired code');
    await p.query('UPDATE users SET password=?, reset_otp=NULL, reset_otp_expires=NULL WHERE id=?', [password, u.id]);
    return { ok: true };
  },

  async findUserByEmail(email) {
    const p = await getPool();
    const [rows] = await p.query('SELECT * FROM users WHERE email=?', [email]);
    const u = rows[0];
    if (u) { u.suspended = !!u.suspended; u.universityId = u.university_id; }
    return u || null;
  },

  async listUniversities() {
    const p = await getPool();
    const [rows] = await p.query('SELECT * FROM universities');
    return Promise.all(rows.map(hydrateUniversity));
  },
  async getUniversity(id) {
    const p = await getPool();
    const [rows] = await p.query('SELECT * FROM universities WHERE id=?', [id]);
    return rows[0] ? hydrateUniversity(rows[0]) : null;
  },

  async listProgrammes(dept) {
    const p = await getPool();
    const [rows] = dept
      ? await p.query('SELECT * FROM programmes WHERE dept=?', [dept])
      : await p.query('SELECT * FROM programmes');
    const real = rows.map(r => ({ id: r.id, name: r.name, dept: r.dept, campus: r.campus || '', years: r.years, universityId: r.university_id }));
    const covered = new Set(real.map(p2 => `${p2.universityId}::${p2.dept}`));
    const [depts] = dept
      ? await p.query('SELECT c.university_id, cd.department, c.name AS campus FROM campus_departments cd JOIN campuses c ON c.id=cd.campus_id WHERE cd.department=?', [dept])
      : await p.query('SELECT c.university_id, cd.department, c.name AS campus FROM campus_departments cd JOIN campuses c ON c.id=cd.campus_id');
    const synthetic = [];
    for (const row of depts) {
      const key = `${row.university_id}::${row.department}`;
      if (covered.has(key)) continue;
      covered.add(key);
      synthetic.push({ id: `dept-${row.university_id}-${slug(row.department)}`, name: row.department, dept: row.department, campus: row.campus, years: null, universityId: row.university_id });
    }
    return [...real, ...synthetic];
  },

  async listStaffRequests() {
    const p = await getPool();
    const [rows] = await p.query('SELECT * FROM staff_requests');
    return rows;
  },
  async confirmStaffRequest(id) {
    const p = await getPool();
    await p.query('UPDATE staff_requests SET status="confirmed" WHERE id=?', [id]);
    const [rows] = await p.query('SELECT * FROM staff_requests WHERE id=?', [id]);
    return rows[0];
  },
  async setStaffRequestStatus(id, status) {
    const p = await getPool();
    await p.query('UPDATE staff_requests SET status=? WHERE id=?', [status, id]);
    const [rows] = await p.query('SELECT * FROM staff_requests WHERE id=?', [id]);
    const r = rows[0];
    if (r) await p.query('UPDATE users SET suspended=? WHERE email=?', [status === 'suspended' ? 1 : 0, r.email]);
    return r;
  },
  async deleteStaffRequest(id) {
    const p = await getPool();
    const [rows] = await p.query('SELECT * FROM staff_requests WHERE id=?', [id]);
    const r = rows[0];
    await p.query('DELETE FROM staff_requests WHERE id=?', [id]);
    if (r) await p.query('DELETE FROM users WHERE email=? AND role="staff"', [r.email]);
    return { ok: true };
  },

  // ---- admin: universities CRUD ----
  async addUniversity({ abbr, name, sector }) {
    const p = await getPool();
    const id = uid('uni');
    await p.query('INSERT INTO universities (id,abbr,name) VALUES (?,?,?)', [id, abbr, name]);
    const cid = uid('camp');
    await p.query('INSERT INTO campuses (id,university_id,name) VALUES (?,?,?)', [cid, id, sector || 'Gasabo Campus']);
    return { id, abbr, name, sector };
  },
  async updateUniversity(id, { abbr, name, sector, photo }) {
    const p = await getPool();
    if (abbr != null || name != null) {
      await p.query('UPDATE universities SET abbr=COALESCE(?,abbr), name=COALESCE(?,name) WHERE id=?', [abbr, name, id]);
    }
    if (photo !== undefined) {
      await p.query('UPDATE universities SET photo=? WHERE id=?', [photo, id]);
    }
    if (sector != null) {
      const [camps] = await p.query('SELECT id FROM campuses WHERE university_id=? LIMIT 1', [id]);
      if (camps.length) await p.query('UPDATE campuses SET name=? WHERE id=?', [sector, camps[0].id]);
      else await p.query('INSERT INTO campuses (id,university_id,name) VALUES (?,?,?)', [uid('camp'), id, sector]);
    }
    return { id, abbr, name, sector, photo };
  },
  async deleteUniversity(id) {
    const p = await getPool();
    await p.query('DELETE FROM universities WHERE id=?', [id]);
    await p.query('DELETE FROM campuses WHERE university_id=?', [id]);
    await p.query('DELETE FROM criteria_values WHERE university_id=?', [id]);
    return { ok: true };
  },

  // ---- admin: criteria CRUD ----
  async listCriteria() {
    const p = await getPool();
    const [rows] = await p.query('SELECT code,label,category,direction FROM criteria ORDER BY code');
    return rows;
  },
  async addCriterion({ label, category, direction }) {
    const p = await getPool();
    const [rows] = await p.query('SELECT code FROM criteria');
    const nums = rows.map(r => parseInt((r.code || '').replace(/\D/g, '')) || 0);
    const code = 'C' + String(Math.max(0, ...nums) + 1).padStart(2, '0');
    await p.query('INSERT INTO criteria (code,label,category,direction) VALUES (?,?,?,?)',
      [code, label, category || 'General', direction || 'benefit']);
    return { code, label, category, direction };
  },
  async updateCriterion(code, { label, category, direction }) {
    const p = await getPool();
    await p.query('UPDATE criteria SET label=COALESCE(?,label), category=COALESCE(?,category), direction=COALESCE(?,direction) WHERE code=?',
      [label, category, direction, code]);
    return { code, label, category, direction };
  },
  async deleteCriterion(code) {
    const p = await getPool();
    await p.query('DELETE FROM criteria WHERE code=?', [code]);
    return { ok: true };
  },

  // ---- admin: subject-combination catalogue CRUD ----
  async listCombinations() {
    const p = await getPool();
    const [rows] = await p.query('SELECT code,subjects FROM combinations ORDER BY code');
    return rows.map(r => ({ code: r.code, subjects: (() => { try { return JSON.parse(r.subjects) || []; } catch { return []; } })() }));
  },
  async addCombination({ code, subjects }) {
    const p = await getPool();
    const c = String(code || '').trim().toUpperCase();
    if (!c) throw new Error('Code is required');
    const [existing] = await p.query('SELECT code FROM combinations WHERE code=?', [c]);
    if (existing.length) throw new Error('That code already exists');
    await p.query('INSERT INTO combinations (code,subjects) VALUES (?,?)', [c, JSON.stringify(Array.isArray(subjects) ? subjects : [])]);
    return { code: c, subjects: subjects || [] };
  },
  async updateCombination(code, { subjects }) {
    const p = await getPool();
    const [existing] = await p.query('SELECT code FROM combinations WHERE code=?', [code]);
    if (!existing.length) throw new Error('Combination not found');
    await p.query('UPDATE combinations SET subjects=? WHERE code=?', [JSON.stringify(Array.isArray(subjects) ? subjects : []), code]);
    return { code, subjects: subjects || [] };
  },
  async deleteCombination(code) {
    const p = await getPool();
    await p.query('DELETE FROM combinations WHERE code=?', [code]);
    // Cascade: every university's staff-set eligibility (programme -> code ->
    // subjects) loses this code too, so nothing references a combination
    // that no longer exists in the catalogue.
    const [rows] = await p.query('SELECT university_id, data FROM staff_data');
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
      if (changed) await p.query('UPDATE staff_data SET data=? WHERE university_id=?', [JSON.stringify(sd), row.university_id]);
    }
    return { ok: true };
  },

  // ---- admin: students ----
  async listStudents() {
    const p = await getPool();
    const [rows] = await p.query('SELECT id,name,email,home,suspended FROM users WHERE role="student"');
    return rows.map(u => ({ id: u.id, name: u.name, email: u.email, home: u.home || '', suspended: !!u.suspended }));
  },
  async setStudentSuspended(id, suspended) {
    const p = await getPool();
    await p.query('UPDATE users SET suspended=? WHERE id=?', [suspended ? 1 : 0, id]);
    return { id, suspended: !!suspended };
  },
  async deleteStudent(id) {
    const p = await getPool();
    await p.query("DELETE FROM users WHERE id=? AND role='student'", [id]);
    return { ok: true };
  },

  // ---- staff: own university data ----
  async _staffData(uniId) {
    const p = await getPool();
    const [rows] = await p.query('SELECT data FROM staff_data WHERE university_id=?', [uniId]);
    if (rows.length) { try { return JSON.parse(rows[0].data); } catch { /* fallthrough */ } }
    return { campuses: [], combos: {}, criteria: {} };
  },
  async _saveStaffData(uniId, data) {
    const p = await getPool();
    await p.query(
      'INSERT INTO staff_data (university_id,data) VALUES (?,?) ON DUPLICATE KEY UPDATE data=VALUES(data)',
      [uniId, JSON.stringify(data)]);
  },
  async getStaffData(uniId) { return this._staffData(uniId); },
  async saveStaffCampuses(uniId, campuses) {
    const p = await getPool();
    const d = await this._staffData(uniId); d.campuses = campuses;
    await this._saveStaffData(uniId, d);
    // sync public campuses
    await p.query('DELETE FROM campuses WHERE university_id=?', [uniId]);
    for (const c of campuses) {
      const cid = uid('camp');
      await p.query('INSERT INTO campuses (id,university_id,name) VALUES (?,?,?)', [cid, uniId, c.name]);
      for (const dep of (c.depts || [])) {
        await p.query('INSERT INTO campus_departments (campus_id,department) VALUES (?,?)', [cid, dep]);
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
    const pool = await getPool();
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const [rows] = await conn.query('SELECT data FROM staff_data WHERE university_id=?', [uniId]);
      let d = { campuses: [], combos: {}, criteria: {} };
      if (rows.length) { try { d = JSON.parse(rows[0].data); } catch { /* fallthrough */ } }
      d.campuses = campuses;
      d.programmes = programmes;
      await conn.query(
        'INSERT INTO staff_data (university_id,data) VALUES (?,?) ON DUPLICATE KEY UPDATE data=VALUES(data)',
        [uniId, JSON.stringify(d)]);
      await conn.query('DELETE FROM campuses WHERE university_id=?', [uniId]);
      for (const c of campuses) {
        const cid = uid('camp');
        await conn.query('INSERT INTO campuses (id,university_id,name) VALUES (?,?,?)', [cid, uniId, c.name]);
        for (const dep of (c.depts || [])) {
          await conn.query('INSERT INTO campus_departments (campus_id,department) VALUES (?,?)', [cid, dep]);
        }
      }
      await conn.query('DELETE FROM programmes WHERE university_id=?', [uniId]);
      for (const pr of programmes) {
        await conn.query('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES (?,?,?,?,?)',
          [uid('prog'), pr.name, pr.dept, uniId, pr.campus || null]);
      }
      await conn.commit();
      return d;
    } catch (e) {
      await conn.rollback();
      throw e;
    } finally {
      conn.release();
    }
  },
  async saveStaffCombos(uniId, combos) {
    const d = await this._staffData(uniId); d.combos = combos;
    await this._saveStaffData(uniId, d); return d;
  },
  async saveStaffProgrammes(uniId, programmes) {
    const p = await getPool();
    const d = await this._staffData(uniId); d.programmes = programmes;
    await this._saveStaffData(uniId, d);
    await p.query('DELETE FROM programmes WHERE university_id=?', [uniId]);
    for (const pr of programmes) {
      await p.query('INSERT INTO programmes (id,name,dept,university_id,campus) VALUES (?,?,?,?,?)',
        [uid('prog'), pr.name, pr.dept, uniId, pr.campus || null]);
    }
    return d;
  },
  async saveStaffCriteria(uniId, criteria) {
    const p = await getPool();
    const d = await this._staffData(uniId); d.criteria = criteria;
    await this._saveStaffData(uniId, d);
    const keep = new Set(Object.keys(criteria).filter(k => /^C\d+$/.test(k) && typeof criteria[k] === 'number'));
    // Clear any previously-stored Cxx value whose code dropped out of this
    // save (e.g. staff removed all bus/moto stops -> C09 must not linger).
    const [existing] = await p.query('SELECT code FROM criteria_values WHERE university_id=?', [uniId]);
    for (const row of existing) {
      if (/^C\d+$/.test(row.code) && !keep.has(row.code)) {
        await p.query('DELETE FROM criteria_values WHERE university_id=? AND code=?', [uniId, row.code]);
      }
    }
    for (const [code, value] of Object.entries(criteria)) {
      if (typeof value !== 'number' || !/^C\d+$/.test(code)) continue;
      await p.query(
        'INSERT INTO criteria_values (university_id,code,value) VALUES (?,?,?) ON DUPLICATE KEY UPDATE value=VALUES(value)',
        [uniId, code, value]);
    }
    return d;
  },
  async staffReport(uniId) {
    const p = await getPool();
    const [apps] = await p.query(
      'SELECT a.home_area, u.name, u.email FROM applications a LEFT JOIN users u ON u.id=a.user_id WHERE a.university_id=?', [uniId]);
    const [[sl]] = await p.query('SELECT COUNT(*) AS n FROM shortlists WHERE university_id=?', [uniId]);
    const [[rt]] = await p.query('SELECT AVG(stars) AS avg, COUNT(*) AS n FROM ratings WHERE university_id=?', [uniId]);
    const applicants = apps.map(a => ({ name: a.name || 'A2 graduate', email: a.email || '', home: a.home_area || '' }));
    const byHome = {};
    applicants.forEach(a => { const h = a.home || 'Unknown'; byHome[h] = (byHome[h] || 0) + 1; });
    return {
      appearedCount: (sl.n || 0) + apps.length,
      shortlistCount: sl.n || 0,
      applyCount: apps.length,
      applicants,
      homeAreas: Object.entries(byHome).map(([home, count]) => ({ home, count })).sort((a, b) => b.count - a.count),
      avgRating: rt.avg != null ? Number(Number(rt.avg).toFixed(2)) : null,
      ratingCount: rt.n || 0,
    };
  },
  async adminReport() {
    const p = await getPool();
    const [unis] = await p.query('SELECT id,abbr,name FROM universities');
    const [applyRows] = await p.query('SELECT university_id, COUNT(*) AS n FROM applications GROUP BY university_id');
    const [slRows] = await p.query('SELECT university_id, COUNT(*) AS n FROM shortlists GROUP BY university_id');
    const applyBy = Object.fromEntries(applyRows.map(r => [r.university_id, r.n]));
    const slBy = Object.fromEntries(slRows.map(r => [r.university_id, r.n]));
    const [apps] = await p.query(
      'SELECT a.home_area, a.university_id, u.name, u.email FROM applications a LEFT JOIN users u ON u.id=a.user_id');
    const [students] = await p.query('SELECT name,email,home,suspended FROM users WHERE role="student"');
    const [staff] = await p.query('SELECT name,email,status FROM staff_requests');
    const [[rt]] = await p.query('SELECT AVG(stars) AS avg FROM ratings');
    const uName = Object.fromEntries(unis.map(u => [u.id, u.name]));
    return {
      universities: unis.map(u => ({ abbr: u.abbr, name: u.name, applications: applyBy[u.id] || 0, shortlists: slBy[u.id] || 0 })),
      applications: apps.map(a => ({ student: a.name || 'A2 graduate', email: a.email || '', university: uName[a.university_id] || a.university_id, home: a.home_area || '', date: '' })),
      students: students.map(s => ({ name: s.name, email: s.email, home: s.home || '', suspended: !!s.suspended })),
      staff: staff.map(s => ({ name: s.name, email: s.email, status: s.status })),
      avgRating: rt.avg != null ? Number(Number(rt.avg).toFixed(2)) : null,
    };
  },

  async recordApplication({ userId, universityId, programmeId, homeArea }) {
    const p = await getPool();
    const id = uid('app');
    await p.query('INSERT INTO applications (id,user_id,university_id,programme_id,home_area) VALUES (?,?,?,?,?)',
      [id, userId, universityId, programmeId, homeArea]);
    return { id };
  },
  async recordShortlist({ userId, universityId }) {
    const p = await getPool();
    await p.query('INSERT IGNORE INTO shortlists (id,user_id,university_id) VALUES (?,?,?)',
      [uid('sl'), userId, universityId]);
    return { ok: true };
  },
  async listShortlist(userId) {
    const p = await getPool();
    const [rows] = await p.query(
      'SELECT u.id,u.abbr,u.name FROM shortlists s JOIN universities u ON u.id=s.university_id WHERE s.user_id=?',
      [userId]);
    return rows;
  },
  async removeShortlist(userId, universityId) {
    const p = await getPool();
    await p.query('DELETE FROM shortlists WHERE user_id=? AND university_id=?', [userId, universityId]);
    return { ok: true };
  },
  async recordRating({ userId, universityId, stars }) {
    const p = await getPool();
    await p.query(
      'INSERT INTO ratings (id,user_id,university_id,stars) VALUES (?,?,?,?) ' +
      'ON DUPLICATE KEY UPDATE stars=VALUES(stars)',
      [uid('rt'), userId, universityId, stars]);
    return { ok: true };
  },

  async recordCriteriaSelections(userId, codes) {
    const p = await getPool();
    for (const code of codes) {
      await p.query('INSERT INTO criteria_selections (id,user_id,code,created_at) VALUES (?,?,?,?)',
        [uid('csel'), userId || null, code, new Date().toISOString()]);
    }
    return { ok: true };
  },
  async criteriaUsageCounts() {
    const p = await getPool();
    const [rows] = await p.query(
      'SELECT cs.code, c.label, COUNT(*) AS count FROM criteria_selections cs ' +
      'LEFT JOIN criteria c ON c.code = cs.code GROUP BY cs.code, c.label ORDER BY count DESC');
    return rows.map(r => ({ code: r.code, label: r.label || r.code, count: r.count }));
  },

  async saveUserLastRanking(userId, ranked, criteria) {
    const p = await getPool();
    await p.query(
      'INSERT INTO user_last_ranking (user_id,university_ids,criteria,updated_at) VALUES (?,?,?,?) ' +
      'ON DUPLICATE KEY UPDATE university_ids=VALUES(university_ids), criteria=VALUES(criteria), updated_at=VALUES(updated_at)',
      [userId, JSON.stringify(ranked), JSON.stringify(criteria || []), new Date().toISOString()]);
    return { ok: true };
  },
  async getUserLastRanking(userId) {
    const p = await getPool();
    const [rows] = await p.query('SELECT university_ids, criteria, updated_at FROM user_last_ranking WHERE user_id=?', [userId]);
    if (!rows.length) return null;
    let ranked = [], criteria = [];
    try { ranked = JSON.parse(rows[0].university_ids) || []; } catch { /* ignore malformed row */ }
    try { criteria = JSON.parse(rows[0].criteria) || []; } catch { /* ignore malformed row */ }
    return { ranked, criteria, updatedAt: rows[0].updated_at };
  },
  async universityPopularity() {
    const p = await getPool();
    const [rows] = await p.query('SELECT university_ids FROM user_last_ranking');
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
