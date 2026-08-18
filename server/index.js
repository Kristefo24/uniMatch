require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');

const db = require('./db');
const { topsis } = require('./topsis');

const PORT = Number(process.env.PORT || 4000);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';

const app = express();
app.use(cors());
app.use(express.json());

// ---- helpers --------------------------------------------------------------
const sign = (user) => jwt.sign(
  { id: user.id, role: user.role, email: user.email, universityId: user.universityId || null },
  JWT_SECRET, { expiresIn: '7d' });

function auth(required = true) {
  return (req, res, next) => {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) { if (required) return res.status(401).json({ error: 'Not signed in' }); req.user = null; return next(); }
    try { req.user = jwt.verify(token, JWT_SECRET); next(); }
    catch { return res.status(401).json({ error: 'Session expired — sign in again' }); }
  };
}
function requireRole(role) {
  return (req, res, next) =>
    req.user && req.user.role === role ? next() : res.status(403).json({ error: 'Not allowed' });
}
// Staff may only touch their own university's data; admin can touch any.
function requireStaffOfUniversity() {
  return (req, res, next) =>
    req.user && (req.user.role === 'admin' ||
      (req.user.role === 'staff' && req.user.universityId === req.params.uniId))
      ? next() : res.status(403).json({ error: 'Not allowed' });
}
const wrap = (fn) => (req, res) => Promise.resolve(fn(req, res)).catch(e => {
  console.error(e);
  res.status(400).json({ error: e.message || 'Request failed' });
});

// ---- auth -----------------------------------------------------------------
app.post('/signup', wrap(async (req, res) => {
  const { name, email, password, role, universityId } = req.body || {};
  if (!name || !email || !password) throw new Error('Name, email and password are required');
  const user = await db.createUser({ name, email, password, role: role || 'student', universityId });
  // Staff must be confirmed by an admin before they can log in — no token yet.
  if (user.role === 'staff') return res.json({ pending: true, user: { name, email, role: 'staff' } });
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role } });
}));

app.post('/login', wrap(async (req, res) => {
  const { email, password } = req.body || {};
  const user = await db.findUserByEmail(email || '');
  if (!user || user.password !== password) throw new Error('Wrong email or password');
  if (user.suspended) return res.status(403).json({ error: 'This account has been suspended. Contact the administrator.' });

  if (user.role === 'staff') {
    const reqs = await db.listStaffRequests();
    const confirmed = reqs.some(r => r.email.toLowerCase() === user.email.toLowerCase() && r.status === 'confirmed');
    if (!confirmed) return res.status(403).json({ error: 'Your staff account is awaiting admin confirmation' });
  }
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role, universityId: user.universityId || null } });
}));

// ---- catalogue (public) ---------------------------------------------------
app.get('/programmes', wrap(async (req, res) => {
  res.json(await db.listProgrammes(req.query.dept));
}));

app.get('/universities/:id', wrap(async (req, res) => {
  const u = await db.getUniversity(req.params.id);
  if (!u) throw new Error('University not found');
  res.json(u);
}));

// Public read of a university's staff-entered answers (campuses/combos/criteria
// blob) — students need this to see accommodation, scholarships, eligibility
// combos etc; only the write side (/staff/:uniId/data) is staff-gated.
app.get('/universities/:id/answers', wrap(async (req, res) => {
  res.json(await db.getStaffData(req.params.id));
}));

// The admin-managed evaluation criteria catalogue, with a hasData flag per
// code so students/staff only see criteria at least one university has
// real values for.
app.get('/criteria', wrap(async (_req, res) => {
  const [criteria, unis] = await Promise.all([db.listCriteria(), db.listUniversities()]);
  res.json(criteria.map(c => ({
    ...c,
    hasData: unis.some(u => u.vals && Object.prototype.hasOwnProperty.call(u.vals, c.code)),
  })));
}));

// ---- ranking (TOPSIS) -----------------------------------------------------
app.post('/rank', auth(false), wrap(async (req, res) => {
  const { universityIds, criteria, preferredReligion } = req.body || {};
  let unis = await db.listUniversities();
  if (Array.isArray(universityIds) && universityIds.length) {
    unis = unis.filter(u => universityIds.includes(u.id));
  }
  // Binary religion/culture match (PRD C25): only overridden when the student
  // actually picked a preference — otherwise C25 keeps whatever (if any)
  // value already lives in vals.
  if (preferredReligion) {
    unis = unis.map(u => ({
      ...u,
      vals: { ...(u.vals || {}), C25: (u.religiousBased && u.religion === preferredReligion) ? 1 : 0 },
    }));
  }
  const ranked = topsis(unis, criteria || [])
    .map(u => ({ id: u.id, abbr: u.abbr, name: u.name, cc: Number(u.cc.toFixed(4)), vals: u.vals || {}, combos: u.combos || {} }));
  const codes = Array.isArray(criteria) ? criteria.map(c => c.code).filter(Boolean) : [];
  if (codes.length) {
    try { await db.recordCriteriaSelections(req.user?.id, codes); } catch (e) { console.error(e); }
  }
  res.json({ ranked });
}));

// ---- student actions (auth) ----------------------------------------------
app.post('/apply', auth(), wrap(async (req, res) => {
  const { universityId, programmeId, homeArea } = req.body || {};
  res.json(await db.recordApplication({ userId: req.user?.id, universityId, programmeId, homeArea }));
}));
app.post('/shortlist', auth(), wrap(async (req, res) => {
  res.json(await db.recordShortlist({ userId: req.user?.id, universityId: req.body.universityId }));
}));
app.get('/shortlist', auth(), wrap(async (req, res) => {
  res.json(await db.listShortlist(req.user?.id));
}));
app.delete('/shortlist/:universityId', auth(), wrap(async (req, res) => {
  res.json(await db.removeShortlist(req.user?.id, req.params.universityId));
}));
app.post('/rate', auth(), wrap(async (req, res) => {
  res.json(await db.recordRating({ userId: req.user?.id, universityId: req.body.universityId, stars: req.body.stars }));
}));

// ---- admin ----------------------------------------------------------------
app.get('/staff-requests', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.listStaffRequests());
}));
app.post('/staff-requests/:id/confirm', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.confirmStaffRequest(req.params.id));
}));
app.post('/staff-requests/:id/status', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.setStaffRequestStatus(req.params.id, (req.body && req.body.status) || 'suspended'));
}));
app.delete('/staff-requests/:id', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.deleteStaffRequest(req.params.id));
}));

// ---- staff: own university data ----
app.get('/staff/:uniId/data', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.getStaffData(req.params.uniId));
}));
app.put('/staff/:uniId/campuses', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffCampuses(req.params.uniId, (req.body && req.body.campuses) || []));
}));
app.put('/staff/:uniId/combos', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffCombos(req.params.uniId, (req.body && req.body.combos) || {}));
}));
app.put('/staff/:uniId/criteria', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffCriteria(req.params.uniId, (req.body && req.body.criteria) || {}));
}));
app.get('/staff/:uniId/report', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.staffReport(req.params.uniId));
}));
app.get('/admin/report', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.adminReport());
}));

// admin: universities CRUD
app.get('/admin/universities', auth(), requireRole('admin'), wrap(async (_req, res) => {
  const list = await db.listUniversities();
  res.json(list.map(u => ({ id: u.id, abbr: u.abbr, name: u.name, sector: u.sector || (u.campuses && u.campuses[0] ? u.campuses[0].name : '') })));
}));
app.post('/admin/universities', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.addUniversity(req.body || {}));
}));
app.put('/admin/universities/:id', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.updateUniversity(req.params.id, req.body || {}));
}));
app.delete('/admin/universities/:id', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.deleteUniversity(req.params.id));
}));

// admin: criteria CRUD
app.get('/admin/criteria', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.listCriteria());
}));
app.post('/admin/criteria', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.addCriterion(req.body || {}));
}));
app.put('/admin/criteria/:code', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.updateCriterion(req.params.code, req.body || {}));
}));
app.delete('/admin/criteria/:code', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.deleteCriterion(req.params.code));
}));
app.get('/admin/criteria-usage', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.criteriaUsageCounts());
}));

// admin: students (suspend / restore)
app.get('/admin/students', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.listStudents());
}));
app.post('/admin/students/:id/suspended', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.setStudentSuspended(req.params.id, !!(req.body && req.body.suspended)));
}));

app.get('/health', (_req, res) => res.json({ ok: true, driver: (process.env.DB_DRIVER || 'json') }));

// ---- forgot password ------------------------------------------------------
// Student/admin: an OTP is "sent" to their email (demo returns it).
// Staff: the reset must be re-confirmed by an admin, so their account goes
// back to pending and they can't log in until confirmed again.
app.post('/forgot-password', wrap(async (req, res) => {
  const { email } = req.body || {};
  const user = await db.findUserByEmail(email || '');
  if (!user) throw new Error('No account found with that email');
  if (user.role === 'staff') {
    const reqs = await db.listStaffRequests();
    const r = reqs.find(x => (x.email || '').toLowerCase() === user.email.toLowerCase());
    if (r) await db.setStaffRequestStatus(r.id, 'pending');
    return res.json({ staff: true });
  }
  // Demo OTP — in production this is emailed, never returned.
  res.json({ staff: false, otp: '123456' });
}));

// ---- boot -----------------------------------------------------------------
(async () => {
  try {
    await db.init();
    app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
  } catch (e) {
    console.error('Failed to start:', e.message);
    process.exit(1);
  }
})();
