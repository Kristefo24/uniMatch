#!/usr/bin/env node
// One-off correction: ULK (Universite Libre de Kigali) is flagged in
// staff_data as religiously affiliated, religion "Seventh-day Adventist" --
// almost certainly copied from AUCA's record. ULK is secular, and the flag
// feeds criterion C25, so a graduate who selects "Religious / cultural
// affiliation" and picks Seventh-day Adventist is currently told ULK matches
// their faith.
//
//   node scripts/fix-ulk-religion.js            # dry run -- reports, writes nothing
//   node scripts/fix-ulk-religion.js --apply    # performs the correction
//
// Backs the whole row up before writing. Connection handling mirrors
// scripts/prune.js, including the public-DNS fallback for the Supabase pooler.
const fs = require('fs');
const path = require('path');
const dns = require('dns');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

dns.setServers(['8.8.8.8', '1.1.1.1']);

const APPLY = process.argv.includes('--apply');
const UNI_ID = 'uni-ulk';

let pg;
try { pg = require('pg'); }
catch { console.error('pg not installed. Run: npm install pg'); process.exit(1); }

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set. Point it at the production database before running.');
  process.exit(1);
}

// pg connects through dns.lookup(), which ignores dns.setServers -- resolve
// the address ourselves and keep the hostname for TLS SNI.
async function connect() {
  const u = new URL(process.env.DATABASE_URL);
  let host = u.hostname;
  try {
    const [ip] = await dns.promises.resolve4(u.hostname);
    if (ip) { host = ip; console.log(`  [dns] ${u.hostname} -> ${ip} (via public resolver)`); }
  } catch (e) {
    console.log(`  [dns] falling back to the system resolver (${e.code})`);
  }
  return new pg.Pool({
    host,
    port: Number(u.port || 5432),
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
    database: u.pathname.replace(/^\//, ''),
    ssl: { rejectUnauthorized: false, servername: u.hostname },
    keepAlive: true, statement_timeout: 60000, query_timeout: 60000,
  });
}

(async () => {
  const pool = await connect();
  const client = await pool.connect();
  try {
    const who = await client.query('select current_database(), inet_server_addr()::text as addr');
    console.log(`  [db] ${who.rows[0].current_database} @ ${who.rows[0].addr}`);

    // staff_data.data is TEXT holding the whole { combos, criteria } blob.
    const { rows } = await client.query('select university_id, data from staff_data where university_id = $1', [UNI_ID]);
    if (!rows.length) { console.error(`No staff_data row for ${UNI_ID}.`); process.exit(1); }

    const blob = JSON.parse(rows[0].data || '{}');
    const criteria = blob.criteria || {};
    console.log('\ncurrent:');
    console.log('  religiousBased =', JSON.stringify(criteria.religiousBased));
    console.log('  religion       =', JSON.stringify(criteria.religion));
    console.log('  C25            =', JSON.stringify(criteria.C25));

    if (criteria.religiousBased !== true) {
      console.log('\nAlready correct -- nothing to do.');
      return;
    }

    // religiousBased stays present as an explicit false: that is a real answer
    // ("not religiously affiliated"), and removing the key instead would make
    // the app treat it as never answered and hide it from the detail page.
    const next = { ...criteria, religiousBased: false, C25: 0 };
    delete next.religion;

    console.log('\nwould become:');
    console.log('  religiousBased =', JSON.stringify(next.religiousBased));
    console.log('  religion       = (removed)');
    console.log('  C25            =', JSON.stringify(next.C25));

    if (!APPLY) {
      console.log('\nDry run. Re-run with --apply to write it.');
      return;
    }

    const dir = path.join(__dirname, '..', 'backups');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `ulk-religion-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    fs.writeFileSync(file, JSON.stringify({ university_id: UNI_ID, data: blob }, null, 2));
    console.log(`\nbacked up to ${file}`);

    await client.query('begin');
    await client.query('update staff_data set data = $2 where university_id = $1',
      [UNI_ID, JSON.stringify({ ...blob, criteria: next })]);
    await client.query('commit');

    const after = await client.query('select data from staff_data where university_id = $1', [UNI_ID]);
    const c = JSON.parse(after.rows[0].data || '{}').criteria || {};
    console.log('\nnow:');
    console.log('  religiousBased =', JSON.stringify(c.religiousBased));
    console.log('  religion       =', JSON.stringify(c.religion));
    console.log('  C25            =', JSON.stringify(c.C25));
  } catch (e) {
    try { await client.query('rollback'); } catch { /* nothing to roll back */ }
    throw e;
  } finally {
    client.release();
    await pool.end();
  }
})().catch(e => { console.error('\nFAILED:', e.message); process.exit(1); });
