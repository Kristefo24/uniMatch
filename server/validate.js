// Input validation shared by every endpoint that accepts user text.
//
// The app validates too, for an immediate message next to the field, but the
// app is only the first line: anything reaching the API directly bypasses it
// entirely. Every rule that matters is enforced here as well.

// Long enough for any real value, short enough that nothing can be used to
// bloat a row or break a layout that renders it.
const MAX = { name: 120, email: 160, label: 120, abbr: 40, uniName: 200, sector: 160, website: 200 };

function str(v) {
  return typeof v === 'string' ? v.trim() : '';
}

/// Trims, rejects empty, and caps length. `field` names the offending input in
/// the error a user will actually read.
function required(v, field, max) {
  const s = str(v);
  if (!s) throw new Error(`${field} is required`);
  if (max && s.length > max) throw new Error(`${field} must be ${max} characters or fewer`);
  return s;
}

function optional(v, field, max) {
  const s = str(v);
  if (!s) return null;
  if (max && s.length > max) throw new Error(`${field} must be ${max} characters or fewer`);
  return s;
}

// Deliberately not RFC 5322: that accepts addresses no mail server will take,
// and the point here is to stop a graduate waiting on a verification code that
// can never arrive. One @, something either side, a dot in the domain.
const EMAIL_RE = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

function email(v, field = 'Email') {
  const s = required(v, field, MAX.email).toLowerCase();
  if (!EMAIL_RE.test(s)) throw new Error(`${field} does not look like a valid address`);
  return s;
}

/// Rwandan mobile numbers are 9 digits after the country code, starting with 7
/// (72/73/78/79). Accepts the three ways people actually write them --
/// 0788888888, 250788888888, +250 788 888 888 -- and returns one canonical
/// form, so the contact shown to graduates is always dialable.
function phone(v, field = 'Phone number') {
  const raw = required(v, field, 24);
  let digits = raw.replace(/\D/g, '');
  // Same rule as the app's field: strip the country code and any leading zero
  // wherever they appear, rather than only at one exact total length.
  if (digits.startsWith('250')) digits = digits.slice(3);
  while (digits.startsWith('0')) digits = digits.slice(1);
  if (digits.length !== 9) {
    throw new Error(`${field} must be 9 digits after +250, e.g. +250 788 888 888`);
  }
  if (!digits.startsWith('7')) {
    throw new Error(`${field} must be a Rwandan mobile number starting with 7`);
  }
  return '+250' + digits;
}

/// Hosts only -- the app prefixes https:// when opening it, so a scheme is
/// optional. Rejects spaces and anything without a dot, which is what actually
/// produces a dead link on the graduate's contact card.
function website(v, field = 'Website') {
  const s = optional(v, field, MAX.website);
  if (!s) return null;
  const host = s.replace(/^https?:\/\//i, '').replace(/\/.*$/, '');
  if (!/^[^\s/@]+\.[^\s/@]+$/.test(host)) {
    throw new Error(`${field} does not look like a valid address, e.g. www.university.ac.rw`);
  }
  return s;
}

/// A whole number inside [min, max]. Used for star ratings, which the app only
/// ever sends as 1-5 but which reach the database unchecked otherwise -- a
/// crafted request could otherwise skew a university's average permanently.
function intInRange(v, field, min, max) {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new Error(`${field} must be a whole number between ${min} and ${max}`);
  }
  return n;
}

function oneOf(v, field, allowed) {
  const s = str(v);
  if (!allowed.includes(s)) throw new Error(`${field} must be one of: ${allowed.join(', ')}`);
  return s;
}

module.exports = { MAX, str, required, optional, email, phone, website, intInRange, oneOf };
