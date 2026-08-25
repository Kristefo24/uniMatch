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
  // Department/programme eligibility is a soft ordering preference now, not a
  // hard filter — every university is still scored (so TOPSIS's vector
  // normalisation is consistent regardless of which department is picked),
  // and results always show at least 5 universities: department matches
  // first, padded with the best-scoring non-matches if fewer than 5 offer
  // the department at all.
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
    .map(u => ({ id: u.id, abbr: u.abbr, name: u.name, photo: u.photo || null, cc: Number(u.cc.toFixed(4)), vals: u.vals || {}, combos: u.combos || {} }));
  if (deptEligibleIds) {
    // Department matches always lead (cc-descending), non-matches pad the
    // tail (never dropped) so the list is never shorter than the full pool.
    const deptMatches = ranked.filter(u => deptEligibleIds.has(u.id));
    const others = ranked.filter(u => !deptEligibleIds.has(u.id));
    // Within deptMatches only: the exact-programme university jumps to #1,
    // but only when it's genuinely competitive (cc within 0.15 of the best
    // in-department alternative) — a big gap means it ranks at its own score
    // instead, per "if the difference of the score is big, it ranks to its
    // position."
    if (exactProgrammeIds) {
      const exactInDept = deptMatches.filter(u => exactProgrammeIds.has(u.id));
      const others2 = deptMatches.filter(u => !exactProgrammeIds.has(u.id));
      if (exactInDept.length && others2.length) {
        const bestExact = exactInDept[0]; // deptMatches is still cc-desc at this point
        const bestOther = others2[0];
        if (bestExact.cc >= bestOther.cc - 0.15) {
          const rest = deptMatches.filter(u => u.id !== bestExact.id);
          ranked = [bestExact, ...rest, ...others];
        } else {
          ranked = [...deptMatches, ...others];
        }
      } else {
        ranked = [...deptMatches, ...others];
      }
    } else {
      ranked = [...deptMatches, ...others];
    }
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
app.get('/admin/criteria-usage', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.criteriaUsageCounts());
}));
app.get('/admin/university-popularity', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.universityPopularity());
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
