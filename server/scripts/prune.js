#!/usr/bin/env node
// One-off maintenance: remove the UR-CMHS university and prune dormant A2
// graduate accounts, bringing the live data in line with the six private
// universities and 121 respondents reported in the dissertation.
//
//   node scripts/prune.js            # dry run -- reports, writes nothing
//   node scripts/prune.js --apply    # performs the deletion
//
// Connects with DATABASE_URL, the same variable db/supabase-driver.js uses.
// Everything it touches is written to a backup file BEFORE any deletion, and
// the whole run is one transaction: any error rolls the lot back.
const fs = require('fs');
const path = require('path');
const dns = require('dns');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// Some ISP/router resolvers fail on the Supabase pooler hostname (ENOTFOUND
// even though the record exists). Fall back to public DNS so a broken local
// resolver doesn't look like a dead database.
// Public resolvers only: leaving the local one first makes Node wait on it and
// fail outright rather than falling through when it times out.
dns.setServers(['8.8.8.8', '1.1.1.1']);

const APPLY = process.argv.includes('--apply');
const UNI_ID = 'uni-urcmhs';
// How many dormant student accounts to delete. Override with --students N;
// 0 removes the university only and leaves every account untouched.
const sIdx = process.argv.indexOf('--students');
const DORMANT_TARGET = sIdx !== -1 ? Number(process.argv[sIdx + 1]) : 58;

let pg;
try { pg = require('pg'); }
catch { console.error('pg not installed. Run: npm install pg'); process.exit(1); }

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set. Point it at the production database before running.');
  process.exit(1);
}

// pg connects through dns.lookup(), which uses the OS resolver and ignores
// dns.setServers -- so on a network whose resolver can't see the Supabase
// pooler host we resolve the address ourselves and connect by IP, keeping the
// original hostname for TLS SNI and certificate validation.
let pool;
async function connect() {
  const u = new URL(process.env.DATABASE_URL);
  let host = u.hostname;
  try {
    const [ip] = await dns.promises.resolve4(u.hostname);
    if (ip) { host = ip; console.log(`  [dns] ${u.hostname} -> ${ip} (via public resolver)`); }
  } catch (e) {
    console.log(`  [dns] falling back to the system resolver (${e.code})`);
  }
  pool = new pg.Pool({
    host,
    port: Number(u.port || 5432),
    user: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
    database: u.pathname.replace(/^\//, ''),
    ssl: { rejectUnauthorized: false, servername: u.hostname },
  });
  return pool;
}
const q = (text, params = []) => pool.query(text, params);
const n = async (sql, params = []) => (await q(sql, params)).rows[0].n;

// A student counts as dormant only when they appear in none of the activity
// tables -- not merely when they have no saved ranking. Anyone who applied,
// shortlisted, rated or even ran a ranking is out of scope.
const DORMANT_SQL = `
  SELECT u.id, u.name, u.email FROM users u
   WHERE u.role = 'student'
     AND NOT EXISTS (SELECT 1 FROM user_last_ranking   r WHERE r.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM applications        a WHERE a.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM shortlists          s WHERE s.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM ratings             t WHERE t.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM criteria_selections c WHERE c.user_id = u.id)
   ORDER BY u.id`;

function hr(title) { console.log('\n' + title + '\n' + '-'.repeat(title.length)); }

(async () => {
  await connect();
  console.log(APPLY ? '*** APPLY MODE -- changes WILL be written ***'
                    : '--- DRY RUN -- nothing will be written (pass --apply to commit) ---');

  // ---------------------------------------------------------------- gather
  hr('Current state');
  const students = await n("SELECT COUNT(*)::int AS n FROM users WHERE role='student'");
  const unis = await n('SELECT COUNT(*)::int AS n FROM universities');
  console.log(`  students: ${students}   universities: ${unis}`);

  hr(`UR-CMHS (${UNI_ID}) rows`);
  const campusIds = (await q('SELECT id FROM campuses WHERE university_id=$1', [UNI_ID])).rows.map(r => r.id);
  const urc = {
    applications: (await q('SELECT * FROM applications  WHERE university_id=$1', [UNI_ID])).rows,
    shortlists:   (await q('SELECT * FROM shortlists    WHERE university_id=$1', [UNI_ID])).rows,
    ratings:      (await q('SELECT * FROM ratings       WHERE university_id=$1', [UNI_ID])).rows,
    criteria_values: (await q('SELECT * FROM criteria_values WHERE university_id=$1', [UNI_ID])).rows,
    programmes:   (await q('SELECT * FROM programmes    WHERE university_id=$1', [UNI_ID])).rows,
    campus_departments: campusIds.length
      ? (await q('SELECT * FROM campus_departments WHERE campus_id = ANY($1)', [campusIds])).rows : [],
    campuses:     (await q('SELECT * FROM campuses     WHERE university_id=$1', [UNI_ID])).rows,
    staff_data:   (await q('SELECT * FROM staff_data   WHERE university_id=$1', [UNI_ID])).rows,
    staff_requests: (await q('SELECT * FROM staff_requests WHERE university_id=$1', [UNI_ID])).rows,
    staff_users:  (await q('SELECT id,name,email,role FROM users WHERE university_id=$1', [UNI_ID])).rows,
    universities: (await q('SELECT * FROM universities WHERE id=$1', [UNI_ID])).rows,
  };
  for (const [t, rows] of Object.entries(urc)) console.log(`  ${String(rows.length).padStart(4)}  ${t}`);

  // saved top-5 snapshots that mention the university
  const snaps = (await q('SELECT user_id, university_ids FROM user_last_ranking')).rows;
  const snapEdits = [];
  for (const s of snaps) {
    let arr;
    try { arr = JSON.parse(s.university_ids); } catch { continue; }
    if (!Array.isArray(arr)) continue;
    const kept = arr.filter(u => u && u.id !== UNI_ID);
    if (kept.length !== arr.length) {
      snapEdits.push({ user_id: s.user_id, before: arr.length, after: kept.length, original: s.university_ids, updated: JSON.stringify(kept) });
    }
  }
  console.log(`  ${String(snapEdits.length).padStart(4)}  saved rankings containing UR-CMHS (will be rewritten)`);

  hr('Dormant students');
  const dormant = (await q(DORMANT_SQL)).rows;
  console.log(`  ${dormant.length} dormant of ${students} students; ${DORMANT_TARGET} required`);
  if (dormant.length < DORMANT_TARGET) {
    console.error(`\nABORT: only ${dormant.length} dormant accounts exist, fewer than the ${DORMANT_TARGET} requested.`);
    console.error('Refusing to delete active accounts to make up the number.');
    await pool.end();
    process.exit(1);
  }
  const toDelete = dormant.slice(0, DORMANT_TARGET);
  console.log(`  selecting the first ${toDelete.length} by id:`);
  for (const u of toDelete.slice(0, 5)) console.log(`     ${u.id}  ${u.email}`);
  if (toDelete.length > 5) console.log(`     … and ${toDelete.length - 5} more`);
  console.log(`  students remaining afterwards: ${students - toDelete.length}`);

  if (!APPLY) {
    hr('Dry run complete');
    console.log('  Re-run with --apply to write these changes.');
    await pool.end();
    return;
  }

  // ---------------------------------------------------------------- backup
  const dir = path.join(__dirname, '..', 'backups');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `prune-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    takenAt: new Date().toISOString(),
    universityRemoved: UNI_ID,
    urcmhs: urc,
    snapshotsRewritten: snapEdits,
    studentsDeleted: toDelete,
    countsBefore: { students, universities: unis },
  }, null, 2));
  const size = fs.statSync(file).size;
  if (!size) { console.error('ABORT: backup file is empty.'); await pool.end(); process.exit(1); }
  hr('Backup written');
  console.log(`  ${file}  (${size} bytes)`);

  // ---------------------------------------------------------------- delete
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const del = async (sql, params, label) => {
      const r = await c.query(sql, params);
      console.log(`  -${String(r.rowCount).padStart(4)}  ${label}`);
    };
    hr('Deleting');
    await del('DELETE FROM applications      WHERE university_id=$1', [UNI_ID], 'applications');
    await del('DELETE FROM shortlists        WHERE university_id=$1', [UNI_ID], 'shortlists');
    await del('DELETE FROM ratings           WHERE university_id=$1', [UNI_ID], 'ratings');
    await del('DELETE FROM criteria_values   WHERE university_id=$1', [UNI_ID], 'criteria_values');
    await del('DELETE FROM programmes        WHERE university_id=$1', [UNI_ID], 'programmes');
    if (campusIds.length) {
      await del('DELETE FROM campus_departments WHERE campus_id = ANY($1)', [campusIds], 'campus_departments');
    }
    await del('DELETE FROM campuses          WHERE university_id=$1', [UNI_ID], 'campuses');
    await del('DELETE FROM staff_data        WHERE university_id=$1', [UNI_ID], 'staff_data');
    await del('DELETE FROM staff_requests    WHERE university_id=$1', [UNI_ID], 'staff_requests');
    await del('DELETE FROM users             WHERE university_id=$1', [UNI_ID], 'staff user accounts');
    await del('DELETE FROM universities      WHERE id=$1',            [UNI_ID], 'universities');

    for (const s of snapEdits) {
      await c.query('UPDATE user_last_ranking SET university_ids=$1 WHERE user_id=$2', [s.updated, s.user_id]);
    }
    console.log(`  ~${String(snapEdits.length).padStart(4)}  saved rankings rewritten`);

    const ids = toDelete.map(u => u.id);
    await del('DELETE FROM users WHERE id = ANY($1)', [ids], 'dormant student accounts');

    await c.query('COMMIT');
    console.log('\nCOMMITTED.');
  } catch (e) {
    await c.query('ROLLBACK');
    console.error('\nROLLED BACK -- nothing was changed. Error:', e.message);
    c.release(); await pool.end(); process.exit(1);
  }
  c.release();

  // ---------------------------------------------------------------- verify
  hr('After');
  console.log(`  students: ${await n("SELECT COUNT(*)::int AS n FROM users WHERE role='student'")}`);
  console.log(`  universities: ${await n('SELECT COUNT(*)::int AS n FROM universities')}`);
  console.log(`  rows still mentioning ${UNI_ID}: ${
    await n('SELECT (SELECT COUNT(*) FROM universities WHERE id=$1) + (SELECT COUNT(*) FROM programmes WHERE university_id=$1) + (SELECT COUNT(*) FROM applications WHERE university_id=$1) AS n', [UNI_ID])}`);
  console.log(`  backup: ${file}`);
  await pool.end();
})().catch(async (e) => { console.error(e); try { await pool.end(); } catch {} process.exit(1); });
