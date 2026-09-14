require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const db = require('./db');
const { topsis, haversineKm } = require('./topsis');
const mailer = require('./mailer');
const ExcelJS = require('exceljs');
const crypto = require('crypto');

// Shared by signup verification and password reset -- both are a 6-digit
// code that expires 2 minutes after it's (re)sent.
const OTP_TTL_MS = 2 * 60 * 1000;
const genOtp = () => String(Math.floor(100000 + Math.random() * 900000));
// Wrong guesses a single code tolerates before it's burned. Without this, a
// 6-digit code is brute-forceable inside its own 2-minute window -- unlimited
// guesses against ~10^6 combinations is not a real barrier, and on
// /reset-password a hit means taking over the account.
const MAX_OTP_ATTEMPTS = 5;
const TOO_MANY_ATTEMPTS = 'Too many incorrect attempts — request a new code.';

// The single gate both OTP flows go through (signup verification and password
// reset). Returns normally only when `supplied` is the stored, unexpired code.
// Otherwise it counts the miss and throws -- and once the limit is reached it
// burns the code via `burn()`, so even the *correct* code stops working until
// a new one is sent. `bump` returns the new attempt count; `burn` invalidates
// the stored code without destroying the surrounding record.
async function checkOtp({ stored, expiresAt, attempts, supplied, bump, burn }) {
  // Re-checked on every call, not just after a bump: the counter is what makes
  // the lockout survive a restart and outlast the burn itself.
  if ((attempts || 0) >= MAX_OTP_ATTEMPTS) throw new Error(TOO_MANY_ATTEMPTS);
  const live = !!expiresAt && new Date(expiresAt).getTime() >= Date.now();
  if (stored && supplied === stored && live) return;
  const now = await bump();
  if (now >= MAX_OTP_ATTEMPTS) {
    await burn();
    throw new Error(TOO_MANY_ATTEMPTS);
  }
  throw new Error('Invalid or expired code');
}

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
  const { name, email, password, role, universityId, track, contactEmail, contactPhone } = req.body || {};
  if (!name || !email || !password) throw new Error('Name, email and password are required');
  if (password.length < 8) throw new Error('Password must be at least 8 characters');
  // Staff signup also registers the university's public contact info —
  // required so every university has it from day one.
  if ((role || 'student') === 'staff' && (!contactEmail || !contactPhone)) {
    throw new Error('University contact email and phone are required');
  }
  const hashed = await bcrypt.hash(password, 10);
  // Staff: unchanged — account created immediately, gated by admin
  // confirmation (no token yet, no email-OTP step for this role).
  if ((role || 'student') === 'staff') {
    const user = await db.createUser({ name, email, password: hashed, role: 'staff', universityId, track });
    if (universityId) await db.setUniversityContacts(universityId, { contactEmail, contactPhone });
    return res.json({ pending: true, user: { name, email, role: 'staff' } });
  }
  // Student: the real account isn't created yet — a code is emailed and
  // must be verified via /verify-signup first. A second signup attempt with
  // the same (still-unverified) email just overwrites the pending one with
  // a fresh code, so a mistyped field or a lost email doesn't strand them.
  if (await db.findUserByEmail(email)) throw new Error('An account with this email already exists');
  const otp = genOtp();
  const otpExpires = new Date(Date.now() + OTP_TTL_MS).toISOString();
  await db.createPendingSignup({ name, email, password: hashed, track, universityId, otp, otpExpires });
  // Not awaited on purpose -- the pending signup already exists (Resend
  // code works regardless), so the response shouldn't wait on a possibly
  // slow/unreachable SMTP connection.
  mailer.sendMail({ to: email, subject: 'Your UniMatch verification code',
    text: `Your UniMatch verification code is ${otp}. It expires in 2 minutes.`,
    html: mailer.otpEmailHtml({ intro: 'Use the code below to verify your UniMatch account:', otp }) })
    .catch(e => console.error('[mailer] signup OTP send failed:', e.message));
  res.json({ needsVerification: true, email });
}));

app.post('/verify-signup', wrap(async (req, res) => {
  const { email, otp } = req.body || {};
  if (!email || !otp) throw new Error('Email and code are required');
  const pending = await db.getPendingSignup(email);
  // Same message as a wrong code, so this can't be used to probe which
  // addresses have a signup in flight.
  if (!pending) throw new Error('Invalid or expired code');
  await checkOtp({
    stored: pending.otp, expiresAt: pending.otpExpires, attempts: pending.attempts, supplied: otp,
    bump: () => db.bumpPendingSignupAttempts(email),
    burn: () => db.clearPendingSignupOtp(email),
  });
  await db.createUser({ name: pending.name, email: pending.email, password: pending.password, role: 'student', universityId: pending.universityId, track: pending.track });
  await db.deletePendingSignup(email);
  res.json({ ok: true });
}));

app.post('/resend-signup-otp', wrap(async (req, res) => {
  const { email } = req.body || {};
  const pending = await db.getPendingSignup(email || '');
  if (!pending) throw new Error('No pending signup found for that email — please sign up again');
  const otp = genOtp();
  const otpExpires = new Date(Date.now() + OTP_TTL_MS).toISOString();
  await db.createPendingSignup({ ...pending, otp, otpExpires });
  mailer.sendMail({ to: pending.email, subject: 'Your UniMatch verification code',
    text: `Your UniMatch verification code is ${otp}. It expires in 2 minutes.`,
    html: mailer.otpEmailHtml({ intro: 'Here is your new UniMatch verification code:', otp }) })
    .catch(e => console.error('[mailer] resend OTP send failed:', e.message));
  res.json({ ok: true });
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

// A university's logo as a real image response rather than a base64 data URI
// inside JSON. Embedded, the seven logos were ~260 KB of every /rank response
// -- ~93% of it -- and a data URI can't be cached, so they were re-sent on
// every ranking. Served here they are fetched once and revalidated cheaply.
app.get('/universities/:id/photo', wrap(async (req, res) => {
  const photo = await db.getUniversityPhoto(req.params.id);
  if (!photo) return res.status(404).json({ error: 'No photo' });
  // Stored as a data URI ("data:image/jpeg;base64,...."); split off the bytes.
  const m = /^data:([^;,]+)?(;base64)?,(.*)$/s.exec(photo);
  const type = (m && m[1]) || 'image/jpeg';
  const body = m ? (m[2] ? Buffer.from(m[3], 'base64') : Buffer.from(decodeURIComponent(m[3])))
                 : Buffer.from(photo, 'base64');
  // Content-addressed ETag: a staff photo change alters the bytes, so the tag
  // changes with it and clients pick the new logo up on their next revalidate.
  const etag = '"' + crypto.createHash('sha1').update(body).digest('hex') + '"';
  res.setHeader('ETag', etag);
  res.setHeader('Cache-Control', 'public, max-age=3600');
  if (req.headers['if-none-match'] === etag) return res.status(304).end();
  res.setHeader('Content-Type', type);
  res.setHeader('Content-Length', body.length);
  res.send(body);
}));

// The admin-managed evaluation criteria catalogue, with a hasData flag per
// code so students/staff only see criteria at least one university has
// real values for.
app.get('/criteria', wrap(async (_req, res) => {
  // criteriaValueStats() answers both questions in a single grouped query.
  // This used to hydrate every university in full -- campuses, ratings, staff
  // blobs and base64 logos -- purely to read two facts per criterion, which
  // made the endpoint the slowest in the app.
  const [criteria, stats] = await Promise.all([db.listCriteria(), db.criteriaValueStats()]);
  res.json(criteria.map(c => {
    const s = stats[c.code];
    return {
      ...c,
      hasData: !!(s && s.hasData),
      // Highest value any university actually has for this criterion -- lets
      // the client size an input to real data (the budget slider's ceiling)
      // instead of a hardcoded guess. null when nobody has a number for it.
      maxValue: s && Number.isFinite(s.max) ? s.max : null,
    };
  }));
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
      id: u.id, abbr: u.abbr, name: u.name, cc: Number(u.cc.toFixed(4)),
      // The logo is fetched from /universities/:id/photo instead of being
      // embedded -- see that endpoint. `hasPhoto` tells the client whether to
      // request one at all, so a university without a logo falls back to its
      // initials badge rather than showing an empty tile after a 404.
      hasPhoto: !!u.photo,
      bestCode: u.bestCode || null, weakCodes: u.weakCodes || [],
      vals: u.vals || {}, combos: u.combos || {},
      // Embedded so the results screen doesn't have to fetch
      // /universities/:id/answers once per ranked university -- that was one
      // extra round trip each, on top of this response.
      staffAnswers: u.staffAnswers || {},
    }));
  if (deptEligibleIds) {
    const deptMatches = ranked.filter(u => deptEligibleIds.has(u.id));
    let filtered;
    // Exact-programme promotion: only boost to #1 when the score gap is under
    // 5 points. A wider gap means the exact-programme university genuinely
    // scores much lower on the criteria the graduate chose — forcing it to #1
    // would hide a better-matching option. Instead, keep the cc-sorted order
    // and let the UI surface "Your programme" on whichever card has it, so
    // the graduate can make an informed choice.
    if (exactProgrammeIds) {
      const exactInDept = deptMatches.filter(u => exactProgrammeIds.has(u.id));
      const others2 = deptMatches.filter(u => !exactProgrammeIds.has(u.id));
      if (exactInDept.length && others2.length) {
        const bestExact = exactInDept[0]; // deptMatches is still cc-desc at this point
        const bestOther = others2[0];
        // Compare the scores the graduate actually sees (cc*100 rounded, exactly
        // as main.dart renders them) so the rule is verifiable from the screen.
        const shownScore = (u) => Math.round(u.cc * 100);
        const showProgrammeReason = shownScore(bestOther) - shownScore(bestExact) < 5;
        if (showProgrammeReason) {
          // Small gap — promote the exact-programme university to #1
          filtered = [bestExact, ...deptMatches.filter(u => u.id !== bestExact.id)]
            .map(u => ({ ...u, hasExactProgramme: exactProgrammeIds.has(u.id), showProgrammeReason: true }));
        } else {
          // Large gap — keep cc-sorted order; mark which university has the programme
          filtered = deptMatches
            .map(u => ({ ...u, hasExactProgramme: exactProgrammeIds.has(u.id), showProgrammeReason: false }));
        }
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
app.get('/me/application', auth(), wrap(async (req, res) => {
  res.json(await db.getMyApplication(req.user?.id));
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
  const r = await db.confirmStaffRequest(req.params.id);
  if (r && r.email) {
    mailer.sendMail({ to: r.email, subject: 'Your UniMatch staff account is confirmed',
      text: 'Your UniMatch staff account has been confirmed — you can now log in.',
      html: mailer.emailTemplate('<p>Your UniMatch staff account has been confirmed — you can now log in.</p>') })
      .catch(e => console.error('[mailer] staff-confirm send failed:', e.message));
  }
  res.json(r);
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

// The university's public contact details, edited from the staff member's own
// "Edit profile" sheet. These are the single source of truth for the three
// fields -- saveStaffCriteria deliberately can't touch them (see the drivers),
// so a stale criteria screen can never wipe or revert what's set here.
app.put('/staff/:uniId/contacts', auth(), requireStaffOfUniversity(), wrap(async (req, res) => {
  const { contactEmail, contactPhone, website } = req.body || {};
  res.json(await db.setUniversityContacts(req.params.uniId, { contactEmail, contactPhone, website }));
}));
app.get('/admin/report', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json(await db.adminReport());
}));

// TEMPORARY diagnostic for the signup-OTP-not-arriving investigation -- reports
// only whether this running process currently sees the mailer credentials, and
// the sending address itself (not a secret -- it's already visible in every
// outgoing email's From header). Never returns BREVO_API_KEY. Remove once
// the delivery issue is resolved.
app.get('/admin/mailer-status', auth(), requireRole('admin'), wrap(async (_req, res) => {
  res.json({
    mailerConfigured: !!(process.env.GMAIL_USER && process.env.BREVO_API_KEY),
    gmailUser: process.env.GMAIL_USER || null,
  });
}));

// A fixed display-only stand-in for a missing/blank application date in
// this one report -- never written back to the database (adminReport()'s
// `date` field for that row stays '' at the source; this only affects what
// the exported workbook shows).
const REPORT_MISSING_DATE = '8/25/2026';

// Capitalizes the first letter of every word -- same normalization as the
// client's _titleCase (app/lib/main.dart), reimplemented here because this
// report is now built server-side.
function titleCase(s) {
  return String(s || '').split(' ').map(w => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w)).join(' ');
}

// Excel worksheet names: <=31 chars, none of \ / ? * [ ] :, not blank, and
// unique within the workbook -- sanitize a university name into one, adding
// a numeric suffix on collision (e.g. two universities truncating to the
// same 31 chars).
function safeSheetName(name, used) {
  let base = String(name || 'Sheet').replace(/[\\/?*[\]:]/g, ' ').trim().slice(0, 31) || 'Sheet';
  let candidate = base;
  let n = 2;
  while (used.has(candidate.toLowerCase())) {
    const suffix = ` (${n++})`;
    candidate = base.slice(0, 31 - suffix.length) + suffix;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

// Real multi-sheet .xlsx for the admin "A2 applicants list" report -- one
// worksheet per university (all universities from adminReport(), even ones
// with zero applicants, so the workbook's sheet list always matches the
// admin's university list), one row per applicant. Reuses adminReport()
// rather than adding a parallel driver method, since it already returns
// applicants pre-joined with student name/email/home/date across all 3
// drivers.
app.get('/admin/report/applicants.xlsx', auth(), requireRole('admin'), wrap(async (_req, res) => {
  const report = await db.adminReport();

  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'UniMatch Gasabo';
  workbook.created = new Date();

  const byUniversity = new Map(); // university display name -> applicant rows
  for (const u of report.universities) byUniversity.set(u.name, []);
  for (const a of report.applications) {
    if (!byUniversity.has(a.university)) byUniversity.set(a.university, []); // stray/unknown universityId, defensive
    byUniversity.get(a.university).push(a);
  }

  const used = new Set();
  const generated = new Date().toISOString().slice(0, 10);
  for (const [uniName, applicants] of byUniversity) {
    const sheet = workbook.addWorksheet(safeSheetName(uniName, used));

    // Title block, then a header row on row 4 -- same shape across every sheet
    // so a reader moving between universities always finds the table in the
    // same place.
    sheet.mergeCells('A1:D1');
    sheet.getCell('A1').value = `${uniName} — A2 applicants`;
    sheet.getCell('A1').font = { name: 'Arial', size: 13, bold: true, color: { argb: 'FF1B1D1B' } };
    sheet.mergeCells('A2:D2');
    sheet.getCell('A2').value = `UniMatch · generated ${generated}`;
    sheet.getCell('A2').font = { name: 'Arial', size: 9, italic: true, color: { argb: 'FF5E625E' } };
    sheet.getRow(1).height = 20;

    sheet.columns = [
      { key: 'student', width: 30 },
      { key: 'email', width: 32 },
      { key: 'home', width: 24 },
      { key: 'date', width: 14 },
    ];

    const head = sheet.getRow(4);
    ['Student', 'Email', 'Home area', 'Date'].forEach((h, i) => {
      const cell = head.getCell(i + 1);
      cell.value = h;
      cell.font = { name: 'Arial', size: 10, bold: true, color: { argb: 'FFFFFFFF' } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F6D3F' } };
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
    });
    head.height = 18;

    applicants.forEach((a, i) => {
      const row = sheet.getRow(5 + i);
      row.getCell(1).value = titleCase(a.student || '');
      row.getCell(2).value = a.email || '';
      row.getCell(3).value = a.home || '';
      row.getCell(4).value = (a.date && String(a.date).trim()) ? a.date : REPORT_MISSING_DATE;
      for (let c = 1; c <= 4; c++) {
        const cell = row.getCell(c);
        cell.font = { name: 'Arial', size: 10 };
        if (i % 2 === 1) cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF2F6F3' } };
        if (c === 4) cell.alignment = { horizontal: 'center' };
      }
    });

    // Thin borders across the whole table, header included.
    const last = 4 + applicants.length;
    const edge = { style: 'thin', color: { argb: 'FFD6D8D4' } };
    for (let r = 4; r <= Math.max(last, 4); r++) {
      for (let c = 1; c <= 4; c++) {
        sheet.getRow(r).getCell(c).border = { top: edge, left: edge, bottom: edge, right: edge };
      }
    }

    const totalRow = sheet.getRow(last + 2);
    totalRow.getCell(1).value = 'Total applicants';
    totalRow.getCell(1).font = { name: 'Arial', size: 10, bold: true };
    // A formula, not a baked number, so the count follows any edits.
    totalRow.getCell(2).value = { formula: `COUNTA(B5:B${Math.max(last, 5)})` };
    totalRow.getCell(2).font = { name: 'Arial', size: 10, bold: true };
    if (!applicants.length) {
      sheet.getCell('A5').value = 'No applicants recorded for this university.';
      sheet.getCell('A5').font = { name: 'Arial', size: 10, italic: true, color: { argb: 'FF5E625E' } };
    }

    sheet.views = [{ state: 'frozen', ySplit: 4 }];
    sheet.autoFilter = { from: 'A4', to: `D${Math.max(last, 4)}` };

    // Read-only: the workbook is a record of what the system held when it was
    // generated, so it opens for anyone but cannot be altered and passed on as
    // if it were still authoritative. Selecting and copying stay allowed.
    await sheet.protect(process.env.REPORT_LOCK_PASSWORD || 'unimatch', {
      selectLockedCells: true,
      selectUnlockedCells: true,
      formatCells: false, formatColumns: false, formatRows: false,
      insertRows: false, insertColumns: false, deleteRows: false, deleteColumns: false,
      sort: false, autoFilter: false, pivotTables: false,
    });
  }

  const buffer = await workbook.xlsx.writeBuffer();
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', 'attachment; filename="a2-applicants.xlsx"');
  res.send(Buffer.from(buffer));
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
// Student/admin: a real, randomly generated OTP (2-minute expiry, matching
// signup) is stored server-side, emailed, and must be verified by
// /reset-password before the password actually changes.
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
  const otp = genOtp();
  const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString();
  await db.setResetOtp(user.id, otp, expiresAt);
  mailer.sendMail({ to: user.email, subject: 'Your UniMatch password reset code',
    text: `Your UniMatch password reset code is ${otp}. It expires in 2 minutes.`,
    html: mailer.otpEmailHtml({ intro: 'Use the code below to reset your UniMatch password:', otp }) })
    .catch(e => console.error('[mailer] reset OTP send failed:', e.message));
  res.json({ staff: false });
}));

app.post('/reset-password', wrap(async (req, res) => {
  const { email, otp, password } = req.body || {};
  if (!email || !otp || !password) throw new Error('Email, code and new password are required');
  if (password.length < 8) throw new Error('Password must be at least 8 characters');
  const rec = await db.getResetOtp(email);
  // Staff never get a reset code issued (see /forgot-password above), so they
  // can't self-reset -- their `otp` is always null and checkOtp rejects it.
  if (!rec) throw new Error('Invalid or expired code');
  await checkOtp({
    stored: rec.otp, expiresAt: rec.expiresAt, attempts: rec.attempts, supplied: otp,
    bump: () => db.bumpResetOtpAttempts(rec.userId),
    burn: () => db.clearResetOtp(rec.userId),
  });
  const hashed = await bcrypt.hash(password, 10);
  await db.changePassword(rec.userId, hashed);
  await db.clearResetOtp(rec.userId);
  res.json({ ok: true });
}));

app.post('/me/change-password', auth(), wrap(async (req, res) => {
  const { currentPassword, newPassword } = req.body || {};
  if (!currentPassword || !newPassword) throw new Error('Current and new password are required');
  if (newPassword.length < 8) throw new Error('New password must be at least 8 characters');
  const user = await db.findUserByEmail(req.user.email);
  if (!user || !(await bcrypt.compare(currentPassword, user.password))) {
    throw new Error('Current password is incorrect');
  }
  const hashed = await bcrypt.hash(newPassword, 10);
  await db.changePassword(user.id, hashed);
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
