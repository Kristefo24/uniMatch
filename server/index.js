require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');

const db = require('./db');
const { topsis, haversineKm } = require('./topsis');

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
  const { name, email, password, role, universityId, track } = req.body || {};
  if (!name || !email || !password) throw new Error('Name, email and password are required');
  const user = await db.createUser({ name, email, password, role: role || 'student', universityId, track });
  // Staff must be confirmed by an admin before they can log in — no token yet.
  if (user.role === 'staff') return res.json({ pending: true, user: { name, email, role: 'staff' } });
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role, track: user.track || null, photo: user.photo || null } });
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
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role, universityId: user.universityId || null, track: user.track || null, photo: user.photo || null } });
}));

app.put('/me', auth(), wrap(async (req, res) => {
  res.json(await db.updateUser(req.user.id, req.body || {}));
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
  const { universityIds, criteria, preferredReligion, dept, homeLat, homeLng, budgetMin, budgetMax } = req.body || {};
  let unis = await db.listUniversities();
  if (Array.isArray(universityIds) && universityIds.length) {
    unis = unis.filter(u => universityIds.includes(u.id));
  }
  // Hard eligibility filter: only universities that actually offer (or, via
  // the department-fallback synthesis in listProgrammes, are treated as
  // offering) the student's chosen department are ranked at all.
  if (dept) {
    const eligible = new Set((await db.listProgrammes(dept)).map(p => p.universityId));
    unis = unis.filter(u => eligible.has(u.id));
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
  // C07: real straight-line distance from the student's picked home location
  // to the university's own pinned location. No schoolLocation set -> leave
  // whatever static value staff already entered.
  if (homeLat != null && homeLng != null) {
    unis = unis.map(u => {
      if (!u.schoolLocation) return u;
      const km = haversineKm(homeLat, homeLng, u.schoolLocation.lat, u.schoolLocation.lng);
      return { ...u, vals: { ...(u.vals || {}), C07: km } };
    });
    // C09 is no longer derived from the student's home here — it's the
    // campus-to-transport distance staff already computed and persisted in
    // PUT /staff/:uniId/criteria, so it flows through u.vals.C09 unmodified.
  }
  // C01: budget-range fit. In range -> best possible cost value (0); outside
  // -> distance to the nearest edge of the range (still smaller = better).
  if (budgetMin != null || budgetMax != null) {
    unis = unis.map(u => {
      const fee = u.vals?.C01;
      if (fee == null) return u;
      let gap = 0;
      if (budgetMax != null && fee > budgetMax) gap = fee - budgetMax;
      else if (budgetMin != null && fee < budgetMin) gap = budgetMin - fee;
      return { ...u, vals: { ...u.vals, C01: gap } };
    });
  }
  const ranked = topsis(unis, criteria || [])
    .map(u => ({ id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, cc: Number(u.cc.toFixed(4)), vals: u.vals || {}, combos: u.combos || {} }));
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
  const criteria = { ...((req.body && req.body.criteria) || {}) };
  // C09: intrinsic campus-to-transport proximity — derived purely from the
  // school/bus/moto pins staff place on the map, never typed in manually.
  // Recomputed in full on every save so a removed pin never leaves a stale
  // distance behind.
  delete criteria.schoolToBusKm;
  delete criteria.schoolToMotoKm;
  delete criteria.C09;
  const school = criteria.schoolLocation;
  const busStops = Array.isArray(criteria.busStops) ? criteria.busStops : [];
  const motoStops = Array.isArray(criteria.motoStops) ? criteria.motoStops : [];
  if (school && school.lat != null && school.lng != null) {
    const nearestKm = stops => stops.length
      ? Math.min(...stops.map(s => haversineKm(school.lat, school.lng, s.lat, s.lng))) : null;
    const busKm = nearestKm(busStops), motoKm = nearestKm(motoStops);
    if (busKm != null) criteria.schoolToBusKm = Number(busKm.toFixed(2));
    if (motoKm != null) criteria.schoolToMotoKm = Number(motoKm.toFixed(2));
    const candidates = [busKm, motoKm].filter(v => v != null);
    if (candidates.length) criteria.C09 = Number(Math.min(...candidates).toFixed(2));
  }
  res.json(await db.saveStaffCriteria(req.params.uniId, criteria));
}));
app.put('/staff/:uniId/programmes', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffProgrammes(req.params.uniId, (req.body && req.body.programmes) || []));
}));
app.get('/staff/:uniId/report', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.staffReport(req.params.uniId));
}));
app.put('/staff/:uniId/photo', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.updateUniversity(req.params.uniId, { photo: (req.body && req.body.photo) || null }));
}));
app.get('/admin/report', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.adminReport());
}));

// admin: universities CRUD
app.get('/admin/universities', auth(), requireRole('admin'), wrap(async (_req, res) => {
  const list = await db.listUniversities();
  res.json(list.map(u => ({ id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, sector: u.sector || (u.campuses && u.campuses[0] ? u.campuses[0].name : '') })));
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
// Student/admin: a real, randomly generated, expiring OTP is stored server-side
// and must be verified by /reset-password before the password actually changes.
// No email provider is configured for this project, so the OTP is returned in
// the response instead of being emailed — wire up a mail service to send it
// for real instead of surfacing it to the client.
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
  const otp = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  await db.setResetOtp(user.id, otp, expiresAt);
  res.json({ staff: false, otp });
}));

app.post('/reset-password', wrap(async (req, res) => {
  const { email, otp, password } = req.body || {};
  if (!email || !otp || !password) throw new Error('Email, code and new password are required');
  await db.resetPassword(email, otp, password);
  res.json({ ok: true });
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
