// JSON-file storage driver — the default, zero-setup backend.
// Implements the repository interface consumed by index.js.
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { freshStore } = require('../seed');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILE = path.join(DATA_DIR, 'store.json');

let db;

// One-time (per row) upgrade of any password still stored in plain text
// (from before hashing was added) to a bcrypt hash. Idempotent.
function migratePlainTextPasswords() {
  let changed = false;
  for (const u of db.users) {
    if (/^\$2[aby]\$/.test(u.password || '')) continue;
    u.password = bcrypt.hashSync(u.password, 10);
    changed = true;
  }
  if (changed) save();
}

function load() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  if (fs.existsSync(FILE)) {
    db = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    // Backfill fields added after an older store.json was first created.
    const base = freshStore();
    if (!db.criteria) { db.criteria = base.criteria; save(); }
    if (!db.combinations) { db.combinations = base.combinations; save(); }
    if (!db.users.some(u => u.role === 'student')) {
      db.users.push(...base.users.filter(u => u.role === 'student')); save();
    }
    if (!db.criteriaSelections) { db.criteriaSelections = []; save(); }
    if (!db.userLastRanking) { db.userLastRanking = {}; save(); }
  } else {
    db = freshStore();
    save();
  }
  migratePlainTextPasswords();
}
function save() {
  fs.writeFileSync(FILE, JSON.stringify(db, null, 2));
}
const uid = (p) => `${p}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

function ratingSummary(uniId) {
  const rows = db.ratings.filter(r => r.universityId === uniId);
  if (!rows.length) return { avgRating: null, ratingCount: 0 };
  const sum = rows.reduce((s, r) => s + r.stars, 0);
  return { avgRating: Number((sum / rows.length).toFixed(2)), ratingCount: rows.length };
}
function staffExtras(uniId) {
  const sd = db.staffData && db.staffData[uniId];
  const c = (sd && sd.criteria) || {};
  return {
    combos: (sd && sd.combos) || {},
    religiousBased: !!c.religiousBased,
    religion: c.religion || null,
    schoolLocation: c.schoolLocation || null,
    busStops: Array.isArray(c.busStops) ? c.busStops : [],
    motoStops: Array.isArray(c.motoStops) ? c.motoStops : [],
    campusPins: (c.campusPins && typeof c.campusPins === 'object') ? c.campusPins : {},
  };
}

module.exports = {
  async init() { load(); },

  async createUser({ name, email, password, role, universityId, track }) {
    if (db.users.find(u => u.email.toLowerCase() === email.toLowerCase())) {
      throw new Error('An account with this email already exists');
    }
    const user = { id: uid('user'), name, email, password, role, universityId: universityId || null, track: track || null };
    db.users.push(user);
    if (role === 'staff') {
      db.staffRequests.push({ id: uid('req'), name, email, universityId: universityId || null, status: 'pending' });
    }
    save();
    return user;
  },

  async findUserByEmail(email) {
    return db.users.find(u => u.email.toLowerCase() === email.toLowerCase()) || null;
  },

  async listUniversities() { return db.universities.map(u => ({ ...u, ...ratingSummary(u.id), ...staffExtras(u.id) })); },
  async getUniversity(id) {
    const u = db.universities.find(x => x.id === id);
    return u ? { ...u, ...ratingSummary(id), ...staffExtras(id) } : null;
  },

  async listProgrammes(dept) {
    const real = dept ? db.programmes.filter(p => p.dept === dept) : db.programmes;
    const covered = new Set(real.map(p => `${p.universityId}::${p.dept}`));
    const synthetic = [];
    for (const u of db.universities) {
      for (const c of (u.campuses || [])) {
        for (const d of (c.depts || [])) {
          if (dept && d !== dept) continue;
          const key = `${u.id}::${d}`;
          if (covered.has(key)) continue;
          covered.add(key);
          synthetic.push({ id: `dept-${u.id}-${slug(d)}`, name: d, dept: d, universityId: u.id, campus: c.name, years: null });
        }
      }
    }
    return [...real, ...synthetic];
  },

  async listStaffRequests() { return db.staffRequests; },
  async confirmStaffRequest(id) {
    const r = db.staffRequests.find(x => x.id === id);
    if (!r) throw new Error('Request not found');
    r.status = 'confirmed';
    save();
    return r;
  },
  async setStaffRequestStatus(id, status) {
    const r = db.staffRequests.find(x => x.id === id);
    if (!r) throw new Error('Request not found');
    r.status = status;
    // Mirror onto the user account so suspended staff can't log in.
    const u = db.users.find(x => x.email.toLowerCase() === (r.email || '').toLowerCase());
    if (u) u.suspended = status === 'suspended';
    save();
    return r;
  },
  async deleteStaffRequest(id) {
    const r = db.staffRequests.find(x => x.id === id);
    db.staffRequests = db.staffRequests.filter(x => x.id !== id);
    if (r) db.users = db.users.filter(u => u.email.toLowerCase() !== (r.email || '').toLowerCase() || u.role !== 'staff');
    save();
    return { ok: true };
  },

  // ---- staff: own university data (campuses, combos, criteria answers) ----
  async getStaffData(uniId) {
    db.staffData = db.staffData || {};
    if (!db.staffData[uniId]) db.staffData[uniId] = { campuses: [], combos: {}, criteria: {} };
    return db.staffData[uniId];
  },
  async saveStaffCampuses(uniId, campuses) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { combos:{}, criteria:{} }), campuses };
    // keep the public university record's campuses in sync
    const u = db.universities.find(x => x.id === uniId);
    if (u) u.campuses = campuses.map(c => ({ name: c.name, depts: c.depts || [] }));
    save();
    return db.staffData[uniId];
  },
  // Saves campuses and programmes together in one write so they can never
  // desync from a partial failure the way two independent requests could
  // (e.g. a deleted campus's programmes surviving because only the
  // campuses save reached the server) — already atomic here since it's one
  // synchronous in-memory mutation plus one save() to disk.
  async saveStaffCampusesAndProgrammes(uniId, campuses, programmes) {
    await this.saveStaffCampuses(uniId, campuses);
    await this.saveStaffProgrammes(uniId, programmes);
    return db.staffData[uniId];
  },
  async saveStaffCombos(uniId, combos) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { campuses:[], criteria:{} }), combos };
    save();
    return db.staffData[uniId];
  },
  async saveStaffProgrammes(uniId, programmes) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { campuses:[], combos:{}, criteria:{} }), programmes };
    db.programmes = db.programmes.filter(p => p.universityId !== uniId);
    for (const p of programmes) {
      db.programmes.push({ id: uid('prog'), name: p.name, dept: p.dept, campus: p.campus || '', years: p.years || null, universityId: uniId });
    }
    save();
    return db.staffData[uniId];
  },
  async saveStaffCriteria(uniId, criteria) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { campuses:[], combos:{} }), criteria };
    const u = db.universities.find(x => x.id === uniId);
    if (u) {
      u.vals = u.vals || {};
      // Clear any Cxx code no longer present in the new payload (e.g. staff
      // removed all bus/moto stops -> C09 must not linger with the old value).
      for (const k of Object.keys(u.vals)) {
        if (/^C\d+$/.test(k) && !Object.prototype.hasOwnProperty.call(criteria, k)) delete u.vals[k];
      }
      const numeric = Object.fromEntries(
        Object.entries(criteria).filter(([k, v]) => typeof v === 'number' && /^C\d+$/.test(k)));
      u.vals = { ...u.vals, ...numeric };
    }
    save();
    return db.staffData[uniId];
  },
  async staffReport(uniId) {
    const apps = db.applications.filter(a => a.universityId === uniId);
    const shortlists = db.shortlists.filter(s => s.universityId === uniId);
    const applicants = apps.map(a => {
      const u = db.users.find(x => x.id === a.userId);
      return { name: u ? u.name : 'A2 graduate', email: u ? u.email : '', home: a.homeArea || (u && u.home) || '' };
    });
    const byHome = {};
    applicants.forEach(a => { const h = a.home || 'Unknown'; byHome[h] = (byHome[h] || 0) + 1; });
    return {
      appearedCount: shortlists.length + apps.length,
      shortlistCount: shortlists.length,
      applyCount: apps.length,
      applicants,
      homeAreas: Object.entries(byHome).map(([home, count]) => ({ home, count })).sort((a, b) => b.count - a.count),
      ...ratingSummary(uniId),
    };
  },

  async adminReport() {
    const uById = Object.fromEntries(db.universities.map(u => [u.id, u]));
    const applications = db.applications.map(a => {
      const u = db.users.find(x => x.id === a.userId);
      const uni = uById[a.universityId];
      return {
        student: u ? u.name : 'A2 graduate',
        email: u ? u.email : '',
        university: uni ? uni.name : a.universityId,
        home: a.homeArea || (u && u.home) || '',
        date: (a.createdAt || '').slice(0, 10),
      };
    });
    const shortlistByUni = {};
    db.shortlists.forEach(s => { shortlistByUni[s.universityId] = (shortlistByUni[s.universityId] || 0) + 1; });
    const applyByUni = {};
    db.applications.forEach(a => { applyByUni[a.universityId] = (applyByUni[a.universityId] || 0) + 1; });
    const avgRating = db.ratings.length
      ? Number((db.ratings.reduce((s, r) => s + r.stars, 0) / db.ratings.length).toFixed(2))
      : null;
    return {
      universities: db.universities.map(u => ({
        abbr: u.abbr, name: u.name,
        applications: applyByUni[u.id] || 0,
        shortlists: shortlistByUni[u.id] || 0,
      })),
      applications,
      students: db.users.filter(u => u.role === 'student')
        .map(u => ({ name: u.name, email: u.email, home: u.home || '', suspended: !!u.suspended })),
      staff: db.staffRequests.map(r => ({ name: r.name, email: r.email, status: r.status })),
      avgRating,
    };
  },

  async recordApplication({ userId, universityId, programmeId, homeArea }) {
    const row = { id: uid('app'), userId, universityId, programmeId, homeArea, createdAt: new Date().toISOString() };
    db.applications.push(row); save(); return row;
  },
  async recordShortlist({ userId, universityId }) {
    if (!db.shortlists.find(s => s.userId === userId && s.universityId === universityId)) {
      db.shortlists.push({ id: uid('sl'), userId, universityId, createdAt: new Date().toISOString() });
      save();
    }
    return { ok: true };
  },
  async listShortlist(userId) {
    const ids = db.shortlists.filter(s => s.userId === userId).map(s => s.universityId);
    return db.universities.filter(u => ids.includes(u.id)).map(u => ({ id: u.id, abbr: u.abbr, name: u.name }));
  },
  async removeShortlist(userId, universityId) {
    db.shortlists = db.shortlists.filter(s => !(s.userId === userId && s.universityId === universityId));
    save();
    return { ok: true };
  },
  async recordRating({ userId, universityId, stars }) {
    const existing = db.ratings.find(r => r.userId === userId && r.universityId === universityId);
    if (existing) existing.stars = stars;
    else db.ratings.push({ id: uid('rt'), userId, universityId, stars, createdAt: new Date().toISOString() });
    save();
    return { ok: true };
  },

  async recordCriteriaSelections(userId, codes) {
    for (const code of codes) {
      db.criteriaSelections.push({ id: uid('csel'), userId: userId || null, code, createdAt: new Date().toISOString() });
    }
    save();
    return { ok: true };
  },
  async criteriaUsageCounts() {
    const counts = {};
    db.criteriaSelections.forEach(s => { counts[s.code] = (counts[s.code] || 0) + 1; });
    const byCode = Object.fromEntries((db.criteria || []).map(c => [c.code, c]));
    return Object.entries(counts)
      .map(([code, count]) => ({ code, label: byCode[code]?.label || code, count }))
      .sort((a, b) => b.count - a.count);
  },

  async saveUserLastRanking(userId, ranked, criteria) {
    db.userLastRanking = db.userLastRanking || {};
    db.userLastRanking[userId] = { ranked, criteria: criteria || [], updatedAt: new Date().toISOString() };
    save();
    return { ok: true };
  },
  async getUserLastRanking(userId) {
    const row = (db.userLastRanking || {})[userId];
    if (!row) return null;
    return { ranked: row.ranked || [], criteria: row.criteria || [], updatedAt: row.updatedAt };
  },
  async universityPopularity() {
    const rows = Object.values(db.userLastRanking || {});
    const counts = {};
    for (const row of rows) {
      for (const u of row.ranked || []) counts[u.id] = (counts[u.id] || 0) + 1;
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

  // ---- admin: universities CRUD ----
  async addUniversity({ abbr, name, sector }) {
    const u = { id: uid('uni'), abbr, name, sector: sector || 'Gasabo Campus',
      campuses: [{ name: sector || 'Gasabo Campus', depts: [] }], vals: {} };
    db.universities.push(u); save(); return u;
  },
  async updateUniversity(id, { abbr, name, sector, photo }) {
    const u = db.universities.find(x => x.id === id);
    if (!u) throw new Error('University not found');
    if (abbr != null) u.abbr = abbr;
    if (name != null) u.name = name;
    if (sector != null) { u.sector = sector; if (u.campuses[0]) u.campuses[0].name = sector; }
    if (photo !== undefined) u.photo = photo;
    save(); return u;
  },
  async deleteUniversity(id) {
    db.universities = db.universities.filter(u => u.id !== id); save(); return { ok: true };
  },

  // ---- admin: criteria CRUD ----
  async listCriteria() { return db.criteria || []; },
  async addCriterion({ label, category, direction }) {
    const nums = (db.criteria || []).map(c => parseInt((c.code || '').replace(/\D/g, '')) || 0);
    const code = 'C' + String(Math.max(0, ...nums) + 1).padStart(2, '0');
    const c = { code, label, category: category || 'General', direction: direction || 'benefit' };
    db.criteria.push(c); save(); return c;
  },
  async updateCriterion(code, { label, category, direction }) {
    const c = db.criteria.find(x => x.code === code);
    if (!c) throw new Error('Criterion not found');
    if (label != null) c.label = label;
    if (category != null) c.category = category;
    if (direction != null) c.direction = direction;
    save(); return c;
  },
  async deleteCriterion(code) {
    db.criteria = db.criteria.filter(c => c.code !== code); save(); return { ok: true };
  },

  // ---- admin: subject-combination catalogue CRUD ----
  async listCombinations() { return db.combinations || []; },
  async addCombination({ code, subjects }) {
    const c = String(code || '').trim().toUpperCase();
    if (!c) throw new Error('Code is required');
    db.combinations = db.combinations || [];
    if (db.combinations.some(x => x.code === c)) throw new Error('That code already exists');
    const row = { code: c, subjects: Array.isArray(subjects) ? subjects : [] };
    db.combinations.push(row); save(); return row;
  },
  async updateCombination(code, { subjects }) {
    const c = (db.combinations || []).find(x => x.code === code);
    if (!c) throw new Error('Combination not found');
    if (subjects != null) c.subjects = Array.isArray(subjects) ? subjects : [];
    save(); return c;
  },
  async deleteCombination(code) {
    db.combinations = (db.combinations || []).filter(c => c.code !== code);
    // Cascade: every university's staff-set eligibility (programme -> code ->
    // subjects) loses this code too, so nothing references a combination
    // that no longer exists in the catalogue.
    db.staffData = db.staffData || {};
    for (const sd of Object.values(db.staffData)) {
      const combos = sd && sd.combos;
      if (!combos || typeof combos !== 'object') continue;
      for (const programme of Object.keys(combos)) {
        if (combos[programme] && typeof combos[programme] === 'object') {
          delete combos[programme][code];
        }
      }
    }
    save(); return { ok: true };
  },

  // ---- self-service profile update ----
  async updateUser(id, { name, track, photo }) {
    const u = db.users.find(x => x.id === id);
    if (!u) throw new Error('User not found');
    if (name != null) u.name = name;
    if (track !== undefined) u.track = track;
    if (photo !== undefined) u.photo = photo;
    save();
    return { id: u.id, name: u.name, track: u.track || null, photo: u.photo || null };
  },

  async setResetOtp(userId, otp, expiresAt) {
    const u = db.users.find(x => x.id === userId);
    if (!u) throw new Error('User not found');
    u.resetOtp = otp;
    u.resetOtpExpires = expiresAt;
    save();
    return { ok: true };
  },
  async resetPassword(email, otp, password) {
    const u = db.users.find(x => x.email.toLowerCase() === (email || '').toLowerCase());
    if (!u || !u.resetOtp || u.resetOtp !== otp) throw new Error('Invalid or expired code');
    if (!u.resetOtpExpires || new Date(u.resetOtpExpires).getTime() < Date.now()) throw new Error('Invalid or expired code');
    u.password = password;
    u.resetOtp = null;
    u.resetOtpExpires = null;
    save();
    return { ok: true };
  },

  // ---- admin: students (suspend / restore) ----
  async listStudents() {
    return db.users.filter(u => u.role === 'student')
      .map(u => ({ id: u.id, name: u.name, email: u.email, home: u.home || '', suspended: !!u.suspended }));
  },
  async setStudentSuspended(id, suspended) {
    const u = db.users.find(x => x.id === id);
    if (!u) throw new Error('Student not found');
    u.suspended = !!suspended; save();
    return { id: u.id, suspended: u.suspended };
  },
  async deleteStudent(id) {
    db.users = db.users.filter(u => !(u.id === id && u.role === 'student')); save();
    return { ok: true };
  },
};
