require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const db = require('./db');
const { topsis, haversineKm } = require('./topsis');

const PORT = Number(process.env.PORT || 4000);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';

const app = express();
app.use(cors());
// Default express.json() body limit is 100kb — a base64-encoded photo
// (especially a PNG, which image_picker's imageQuality doesn't recompress)
// can exceed that even after resizing to a small thumbnail. A rejected body
// used to fall through to Express's default HTML error page, which the
// client then failed to parse as JSON ("Unexpected token '<'").
app.use(express.json({ limit: '8mb' }));

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
  const hashed = await bcrypt.hash(password, 10);
  const user = await db.createUser({ name, email, password: hashed, role: role || 'student', universityId, track });
  // Staff must be confirmed by an admin before they can log in — no token yet.
  if (user.role === 'staff') return res.json({ pending: true, user: { name, email, role: 'staff' } });
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role, track: user.track || null, photo: user.photo || null } });
}));

app.post('/login', wrap(async (req, res) => {
  const { email, password } = req.body || {};
  const user = await db.findUserByEmail(email || '');
  if (!user || !(await bcrypt.compare(password || '', user.password))) throw new Error('Wrong email or password');
  // A suspended student is let in (not blocked at the door) -- the client
  // locks their home screen and shows the admin's comment instead. Staff's
  // separate "confirmed" gate below is a different mechanism, untouched.

  if (user.role === 'staff') {
    const reqs = await db.listStaffRequests();
    const confirmed = reqs.some(r => r.email.toLowerCase() === user.email.toLowerCase() && r.status === 'confirmed');
    if (!confirmed) return res.status(403).json({ error: 'Your staff account is awaiting admin confirmation' });
  }
  res.json({ token: sign(user), user: { id: user.id, name: user.name, email: user.email, role: user.role, universityId: user.universityId || null, track: user.track || null, photo: user.photo || null,
    homeArea: user.homeArea ?? user.home_area ?? null,
    homeLat: user.homeLat ?? user.home_lat ?? null,
    homeLng: user.homeLng ?? user.home_lng ?? null,
    suspended: !!user.suspended,
    suspendReason: user.suspendReason ?? user.suspend_reason ?? null } });
}));

app.put('/me', auth(), wrap(async (req, res) => {
  res.json(await db.updateUser(req.user.id, req.body || {}));
}));
// The student's own last saved ranking snapshot (top-5, with criteria used) —
// lets "My rankings" show a real result after a fresh login/session, instead
// of only the current in-memory session's result.
app.get('/me/last-ranking', auth(), wrap(async (req, res) => {
  res.json(await db.getUserLastRanking(req.user.id));
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

// The admin-managed subject-combination catalogue (e.g. PCB, MPC) — every A2
// graduate's track picker and every staff programme-eligibility screen reads
// from this instead of a hardcoded list.
app.get('/combinations', wrap(async (_req, res) => {
  res.json(await db.listCombinations());
}));

// ---- ranking (TOPSIS) -----------------------------------------------------
app.post('/rank', auth(false), wrap(async (req, res) => {
  const { universityIds, criteria, preferredReligion, dept, programme, homeLat, homeLng, budgetMin, budgetMax } = req.body || {};
  let unis = await db.listUniversities();
  if (Array.isArray(universityIds) && universityIds.length) {
    unis = unis.filter(u => universityIds.includes(u.id));
  }
  // Department/programme eligibility is a hard filter: a university that
  // doesn't offer the graduate's chosen department is excluded from the
  // ranked list entirely (it's not a real option), so results can genuinely
  // be fewer than 5. Every university is still SCORED first (so TOPSIS's
  // vector normalisation stays consistent regardless of which department is
  // picked) -- only the final list is filtered down. If that filter ever
  // comes up empty (a rare edge case: data changed underneath, a stale
  // saved-ranking replay, or a direct API call bypassing the app's own
  // eligibility gate), fall back to the best-scoring universities overall
  // rather than showing a graduate a blank screen, each flagged
  // `outsideDept: true` so the fallback is never mistaken for a real match.
  let deptEligibleIds = null;
  let exactProgrammeIds = null;
  let deptProgs = null;
  if (dept) {
    deptProgs = await db.listProgrammes(dept);
    deptEligibleIds = new Set(deptProgs.map(p => p.universityId));
    if (programme) exactProgrammeIds = new Set(deptProgs.filter(p => p.name === programme).map(p => p.universityId));
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
  // C07/C09: resolve which campus of each university is actually relevant to
  // this graduate's chosen dept/programme, then use THAT campus's pins —
  // never a different campus's. Exact programme picked -> that programme's
  // own campus, always. Dept only, offered at multiple campuses -> nearest
  // campus to the graduate's home. No dept context or no pins yet -> fall
  // back to the university-wide legacy pin / whatever static value staff
  // already entered.
  const resolveCampusForUni = (u) => {
    if (programme && dept) {
      const exact = (deptProgs || []).find(p => p.universityId === u.id && p.name === programme && p.campus);
      if (exact) return exact.campus;
    }
    if (dept && Array.isArray(u.campuses) && u.campuses.length) {
      const offering = u.campuses.filter(c => Array.isArray(c.depts) && c.depts.includes(dept));
      if (offering.length === 1) return offering[0].name;
      if (offering.length > 1) {
        if (homeLat != null && homeLng != null) {
          let best = null, bestKm = Infinity;
          for (const c of offering) {
            const pin = (u.campusPins || {})[c.name];
            if (!pin || !pin.schoolLocation) continue;
            const km = haversineKm(homeLat, homeLng, pin.schoolLocation.lat, pin.schoolLocation.lng);
            if (km < bestKm) { bestKm = km; best = c.name; }
          }
          if (best) return best;
        }
        return offering[0].name;
      }
    }
    return null;
  };
  unis = unis.map(u => {
    const campusName = resolveCampusForUni(u);
    const pin = campusName ? (u.campusPins || {})[campusName] : null;
    let vals = u.vals || {};
    let changed = false;
    if (pin && pin.C09 != null) { vals = { ...vals, C09: pin.C09 }; changed = true; }
    if (homeLat != null && homeLng != null) {
      if (pin && pin.schoolLocation) {
        vals = { ...vals, C07: haversineKm(homeLat, homeLng, pin.schoolLocation.lat, pin.schoolLocation.lng) };
        changed = true;
      } else if (u.schoolLocation) {
        vals = { ...vals, C07: haversineKm(homeLat, homeLng, u.schoolLocation.lat, u.schoolLocation.lng) };
        changed = true;
      }
    }
    return changed ? { ...u, vals } : u;
  });
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
  let ranked = topsis(unis, criteria || [])
    .map(u => ({
      id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, cc: Number(u.cc.toFixed(4)),
      bestCode: u.bestCode || null, weakCodes: u.weakCodes || [],
      vals: u.vals || {}, combos: u.combos || {},
    }));
  if (deptEligibleIds) {
    const deptMatches = ranked.filter(u => deptEligibleIds.has(u.id));
    let filtered;
    // Within deptMatches only: the university offering the graduate's exact
    // chosen programme always jumps to #1 -- the score gap no longer decides
    // *whether* it's promoted. The same gap is still computed (`showProgrammeReason`)
    // so the UI can tell whether the promotion was genuinely competitive
    // (cc within 0.15 of the best alternative) or a big jump, and choose its
    // Strongest/Weak messaging accordingly -- it just no longer gates the
    // ranking itself.
    if (exactProgrammeIds) {
      const exactInDept = deptMatches.filter(u => exactProgrammeIds.has(u.id));
      const others2 = deptMatches.filter(u => !exactProgrammeIds.has(u.id));
      if (exactInDept.length && others2.length) {
        const bestExact = exactInDept[0]; // deptMatches is still cc-desc at this point
        const bestOther = others2[0];
        const showProgrammeReason = bestExact.cc >= bestOther.cc - 0.15;
        filtered = [bestExact, ...deptMatches.filter(u => u.id !== bestExact.id)]
          .map(u => ({ ...u, hasExactProgramme: exactProgrammeIds.has(u.id), showProgrammeReason }));
      } else {
        filtered = deptMatches.map(u => ({ ...u, hasExactProgramme: exactProgrammeIds.has(u.id) }));
      }
    } else {
      filtered = deptMatches;
    }
    // Rare edge case (see comment above `deptEligibleIds`) -- never show a
    // graduate a blank result screen; fall back to the best overall,
    // clearly flagged as outside their chosen department.
    ranked = filtered.length ? filtered : ranked.map(u => ({ ...u, outsideDept: true }));
  }
  const codes = Array.isArray(criteria) ? criteria.map(c => c.code).filter(Boolean) : [];
  if (codes.length) {
    try { await db.recordCriteriaSelections(req.user?.id, codes); } catch (e) { console.error(e); }
    if (req.user && req.user.role === 'student') {
      try { await db.saveUserLastRanking(req.user.id, ranked.slice(0, 5), criteria); } catch (e) { console.error(e); }
    }
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
app.get('/rate/:universityId', auth(), wrap(async (req, res) => {
  res.json(await db.myRating({ userId: req.user.id, universityId: req.params.universityId }));
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
// Saves campuses and programmes together in one atomic request — used by
// StaffCampusesScreen instead of two separate PUTs, so a network hiccup
// can never leave one saved and the other not (see saveStaffCampusesAndProgrammes).
app.put('/staff/:uniId/campuses-programmes', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffCampusesAndProgrammes(
    req.params.uniId,
    (req.body && req.body.campuses) || [],
    (req.body && req.body.programmes) || [],
  ));
}));
app.put('/staff/:uniId/combos', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffCombos(req.params.uniId, (req.body && req.body.combos) || {}));
}));
app.put('/staff/:uniId/criteria', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  const criteria = { ...((req.body && req.body.criteria) || {}) };
  // C09: intrinsic campus-to-transport proximity — derived purely from the
  // school/bus/moto pins staff place on the map, per campus, never typed in
  // manually. Recomputed in full on every save so a removed pin never
  // leaves a stale distance behind. criteria.C09 (top-level) is kept as a
  // university-wide fallback = the best (lowest) C09 across all campuses,
  // for any code path that isn't campus-aware.
  delete criteria.schoolToBusKm;
  delete criteria.schoolToMotoKm;
  delete criteria.C09;
  const campusPins = (criteria.campusPins && typeof criteria.campusPins === 'object') ? criteria.campusPins : {};
  const resolvedPins = {};
  let bestC09 = null;
  for (const [campusName, p] of Object.entries(campusPins)) {
    const pin = { ...(p || {}) };
    const school = pin.schoolLocation;
    const busStops = Array.isArray(pin.busStops) ? pin.busStops : [];
    const motoStops = Array.isArray(pin.motoStops) ? pin.motoStops : [];
    if (school && school.lat != null && school.lng != null) {
      const nearestKm = stops => stops.length
        ? Math.min(...stops.map(s => haversineKm(school.lat, school.lng, s.lat, s.lng))) : null;
      const busKm = nearestKm(busStops), motoKm = nearestKm(motoStops);
      if (busKm != null) pin.schoolToBusKm = Number(busKm.toFixed(2));
      if (motoKm != null) pin.schoolToMotoKm = Number(motoKm.toFixed(2));
      const candidates = [busKm, motoKm].filter(v => v != null);
      if (candidates.length) {
        pin.C09 = Number(Math.min(...candidates).toFixed(2));
        bestC09 = bestC09 == null ? pin.C09 : Math.min(bestC09, pin.C09);
      }
    }
    resolvedPins[campusName] = pin;
  }
  criteria.campusPins = resolvedPins;
  if (bestC09 != null) criteria.C09 = bestC09;
  res.json(await db.saveStaffCriteria(req.params.uniId, criteria));
}));
app.put('/staff/:uniId/programmes', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.saveStaffProgrammes(req.params.uniId, (req.body && req.body.programmes) || []));
}));
// Renames a programme by name everywhere it's referenced -- the programmes
// table/blob AND its combos entry -- so a rename from the Combinations
// screen can never re-orphan itself the way a plain combos-key edit would.
app.put('/staff/:uniId/programmes/rename', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  const { oldName, newName } = req.body || {};
  if (!oldName || !newName) throw new Error('oldName and newName are required');
  res.json(await db.renameStaffProgramme(req.params.uniId, oldName, newName));
}));
// Removes a programme by name everywhere it's referenced -- the programmes
// table/blob AND its combos entry -- not just its combinations.
app.delete('/staff/:uniId/programmes/:name', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.deleteStaffProgramme(req.params.uniId, req.params.name));
}));
app.get('/staff/:uniId/report', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.staffReport(req.params.uniId));
}));
app.get('/staff/:uniId/criteria-usage', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.staffCriteriaUsage(req.params.uniId));
}));
app.get('/staff/:uniId/combos-reached', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  res.json(await db.staffCombosReached(req.params.uniId));
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

// admin: subject-combination catalogue CRUD
app.get('/admin/combinations', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.listCombinations());
}));
app.post('/admin/combinations', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.addCombination(req.body || {}));
}));
app.put('/admin/combinations/:code', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.updateCombination(req.params.code, req.body || {}));
}));
app.delete('/admin/combinations/:code', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.deleteCombination(req.params.code));
}));
app.get('/admin/criteria-usage', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.criteriaUsageCounts(req.query.universityId || null));
}));
app.get('/admin/university-popularity', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.universityPopularity());
}));

// admin: students (suspend / restore)
app.get('/admin/students', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.listStudents());
}));
app.post('/admin/students/:id/suspended', auth(), requireRole('admin'), wrap(async (req, res) => {
  const suspended = !!(req.body && req.body.suspended);
  if (suspended && !(req.body && req.body.reason && req.body.reason.trim())) {
    const e = new Error('A reason is required to suspend an account.'); e.status = 400; throw e;
  }
  res.json(await db.setStudentSuspended(req.params.id, suspended, req.body && req.body.reason));
}));
app.delete('/admin/students/:id', auth(), requireRole('admin'), wrap(async (req, res) => {
  res.json(await db.deleteStudent(req.params.id));
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
  const hashed = await bcrypt.hash(password, 10);
  await db.resetPassword(email, otp, hashed);
  res.json({ ok: true });
}));

// Catches body-parser failures (oversized or malformed JSON) and anything
// else Express would otherwise answer with its default HTML error page —
// callers only ever get a real, parseable JSON error from this API.
app.use((err, _req, res, _next) => {
  if (err && err.type === 'entity.too.large') {
    return res.status(413).json({ error: 'That file is too large. Try a smaller photo.' });
  }
  console.error(err);
  res.status(err && err.status ? err.status : 400).json({ error: (err && err.message) || 'Request failed' });
});

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
