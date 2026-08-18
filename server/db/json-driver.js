// JSON-file storage driver — the default, zero-setup backend.
// Implements the repository interface consumed by index.js.
const fs = require('fs');
const path = require('path');
const { freshStore } = require('../seed');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILE = path.join(DATA_DIR, 'store.json');

let db;

function load() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  if (fs.existsSync(FILE)) {
    db = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    // Backfill fields added after an older store.json was first created.
    const base = freshStore();
    if (!db.criteria) { db.criteria = base.criteria; save(); }
    if (!db.users.some(u => u.role === 'student')) {
      db.users.push(...base.users.filter(u => u.role === 'student')); save();
    }
    if (!db.criteriaSelections) { db.criteriaSelections = []; save(); }
  } else {
    db = freshStore();
    save();
  }
}
function save() {
  fs.writeFileSync(FILE, JSON.stringify(db, null, 2));
}
const uid = (p) => `${p}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

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
  };
}

module.exports = {
  async init() { load(); },

  async createUser({ name, email, password, role, universityId }) {
    if (db.users.find(u => u.email.toLowerCase() === email.toLowerCase())) {
      throw new Error('An account with this email already exists');
    }
    const user = { id: uid('user'), name, email, password, role, universityId: universityId || null };
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
    return dept ? db.programmes.filter(p => p.dept === dept) : db.programmes;
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
  async saveStaffCombos(uniId, combos) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { campuses:[], criteria:{} }), combos };
    save();
    return db.staffData[uniId];
  },
  async saveStaffCriteria(uniId, criteria) {
    db.staffData = db.staffData || {};
    db.staffData[uniId] = { ...(db.staffData[uniId] || { campuses:[], combos:{} }), criteria };
    const u = db.universities.find(x => x.id === uniId);
    if (u) {
      const numeric = Object.fromEntries(
        Object.entries(criteria).filter(([k, v]) => typeof v === 'number' && /^C\d+$/.test(k)));
      u.vals = { ...(u.vals || {}), ...numeric };
    }
    save();
    return db.staffData[uniId];
  },
  async staffReport(uniId) {
    const apps = db.applications.filter(a => a.universityId === uniId);
    const shortlists = db.shortlists.filter(s => s.universityId === uniId);
    return {
      appearedCount: shortlists.length + apps.length,
      applyCount: apps.length,
      applicants: apps.map(a => {
        const u = db.users.find(x => x.id === a.userId);
        return { name: u ? u.name : 'A2 graduate', email: u ? u.email : '', home: a.homeArea || (u && u.home) || '' };
      }),
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

  // ---- admin: universities CRUD ----
  async addUniversity({ abbr, name, sector }) {
    const u = { id: uid('uni'), abbr, name, sector: sector || 'Gasabo Campus',
      campuses: [{ name: sector || 'Gasabo Campus', depts: [] }], vals: {} };
    db.universities.push(u); save(); return u;
  },
  async updateUniversity(id, { abbr, name, sector }) {
    const u = db.universities.find(x => x.id === id);
    if (!u) throw new Error('University not found');
    if (abbr != null) u.abbr = abbr;
    if (name != null) u.name = name;
    if (sector != null) { u.sector = sector; if (u.campuses[0]) u.campuses[0].name = sector; }
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
};
