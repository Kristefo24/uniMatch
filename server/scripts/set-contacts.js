#!/usr/bin/env node
// Sets a university's public contact details from the command line, for the
// cases where the details arrive before that university's officer has an
// account to enter them himself. Everything here is also editable in the app
// under Edit profile, which is the normal route.
//
//   node scripts/set-contacts.js uni-kepler --phone 250782637318
//   node scripts/set-contacts.js uni-kepler --phone 250782637318 --apply
//   node scripts/set-contacts.js uni-kepler --email info@x.ac.rw --applyUrl https://...
//
// Dry run unless --apply is passed. Backs the row up before writing, and
// validates with the same rules the API uses, so nothing lands here that the
// app would have rejected.
const fs = require('fs');
const path = require('path');
const dns = require('dns');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const v = require('../validate');

dns.setServers(['8.8.8.8', '1.1.1.1']);

const argv = process.argv.slice(2);
const APPLY = argv.includes('--apply');
const UNI_ID = argv.find(a => !a.startsWith('--'));
const arg = (name) => {
  const i = argv.indexOf('--' + name);
  return i === -1 ? null : argv[i + 1];
};

if (!UNI_ID) {
  console.error('Usage: node scripts/set-contacts.js <universityId> [--phone N] [--email E] [--website W] [--applyUrl U] [--apply]');
  process.exit(1);
}

let pg;
try { pg = require('pg'); }
catch { console.error('pg not installed. Run: npm install pg'); process.exit(1); }
if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set.');
  process.exit(1);
}

async function connect() {
  const u = new URL(process.env.DATABASE_URL);
  let host = u.hostname;
  try {
    const [ip] = await dns.promises.resolve4(u.hostname);
    if (ip) { host = ip; console.log(`  [dns] ${u.hostname} -> ${ip}`); }
  } catch (e) { console.log(`  [dns] system resolver (${e.code})`); }
  return new pg.Pool({
    host, port: Number(u.port || 5432),
    user: decodeURIComponent(u.username), password: decodeURIComponent(u.password),
    database: u.pathname.replace(/^\//, ''),
    ssl: { rejectUnauthorized: false, servername: u.hostname },
  });
}

(async () => {
  const pool = await connect();
  const client = await pool.connect();
  try {
    const { rows } = await client.query(
      'select s.data, x.abbr, x.name from staff_data s join universities x on x.id = s.university_id where s.university_id = $1',
      [UNI_ID]);
    if (!rows.length) { console.error(`No staff_data row for ${UNI_ID}.`); process.exit(1); }

    const blob = JSON.parse(rows[0].data || '{}');
    const criteria = blob.criteria || {};
    console.log(`\n${rows[0].abbr} — ${rows[0].name}`);
    console.log('current:');
    for (const k of ['contactPhone', 'contactEmail', 'website', 'applyUrl']) {
      console.log('  ' + k.padEnd(14) + (criteria[k] || '(none)'));
    }

    const next = { ...criteria };
    if (arg('phone')) next.contactPhone = v.phone(arg('phone'), 'Phone');
    if (arg('email')) next.contactEmail = v.email(arg('email'), 'Email');
    if (arg('website')) next.website = v.website(arg('website'), 'Website');
    if (arg('applyUrl')) next.applyUrl = v.website(arg('applyUrl'), 'Application link');

    const changed = Object.keys(next).filter(k => next[k] !== criteria[k]);
    if (!changed.length) { console.log('\nNothing to change.'); return; }
    console.log('\nwould become:');
    for (const k of changed) console.log('  ' + k.padEnd(14) + next[k]);

    if (!APPLY) { console.log('\nDry run. Re-run with --apply to write it.'); return; }

    const dir = path.join(__dirname, '..', 'backups');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `contacts-${UNI_ID}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    fs.writeFileSync(file, JSON.stringify({ university_id: UNI_ID, data: blob }, null, 2));
    console.log(`\nbacked up to ${file}`);

    await client.query('update staff_data set data = $2 where university_id = $1',
      [UNI_ID, JSON.stringify({ ...blob, criteria: next })]);

    const after = JSON.parse(
      (await client.query('select data from staff_data where university_id = $1', [UNI_ID])).rows[0].data || '{}');
    console.log('\nnow:');
    for (const k of ['contactPhone', 'contactEmail', 'website', 'applyUrl']) {
      console.log('  ' + k.padEnd(14) + ((after.criteria || {})[k] || '(none)'));
    }
  } finally {
    client.release();
    await pool.end();
  }
})().catch(e => { console.error('\nFAILED:', e.message); process.exit(1); });
