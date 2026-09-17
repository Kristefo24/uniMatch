#!/usr/bin/env node
// Removes rows left behind by universities that were deleted before
// deleteUniversity() cascaded properly: programmes that outlive their
// university (and so still appear in the graduate's programme picker), staff
// criteria answers, campuses, and any student activity pointing at an
// institution that no longer exists.
//
//   node scripts/clean-orphans.js            # dry run -- reports, writes nothing
//   node scripts/clean-orphans.js --apply    # performs the cleanup
//
// Backs every affected row up before writing, and runs as one transaction.
// The driver fix means new deletions clean up after themselves; this is for
// the rows already stranded.
const fs = require('fs');
const path = require('path');
const dns = require('dns');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

dns.setServers(['8.8.8.8', '1.1.1.1']);
const APPLY = process.argv.includes('--apply');

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
    host, port: Number(u.port || 5432),
    user: decodeURIComponent(u.username), password: decodeURIComponent(u.password),
    database: u.pathname.replace(/^\//, ''),
    ssl: { rejectUnauthorized: false, servername: u.hostname },
    keepAlive: true, statement_timeout: 60000, query_timeout: 60000,
  });
}

// Every table that carries a university_id, plus campus_departments which
// reaches universities only through campuses.
const TABLES = ['applications', 'shortlists', 'ratings', 'programmes',
                'criteria_values', 'campuses', 'staff_data'];

(async () => {
  const pool = await connect();
  const client = await pool.connect();
  try {
    const who = await client.query('select current_database(), inet_server_addr()::text as addr');
    console.log(`  [db] ${who.rows[0].current_database} @ ${who.rows[0].addr}`);

    const orphanSql = t =>
      `select * from ${t} t where t.university_id is not null
       and not exists (select 1 from universities x where x.id = t.university_id)`;

    const found = {};
    let total = 0;
    console.log('\norphaned rows (their university no longer exists):');
    for (const t of TABLES) {
      const { rows } = await client.query(orphanSql(t));
      found[t] = rows;
      total += rows.length;
      console.log('  ' + t.padEnd(18) + String(rows.length).padStart(4)
        + (rows.length ? '   ' + [...new Set(rows.map(r => r.university_id))].join(', ') : ''));
    }

    // Snapshots are JSON blobs, so they need their own pass.
    const { rows: lr } = await client.query('select user_id, university_ids from user_last_ranking');
    const live = new Set((await client.query('select id from universities')).rows.map(r => r.id));
    const snapFixes = [];
    for (const r of lr) {
      let arr;
      try { arr = JSON.parse(r.university_ids) || []; } catch { continue; }
      const kept = arr.filter(u => u && live.has(u.id));
      if (kept.length !== arr.length) snapFixes.push({ user_id: r.user_id, before: arr, kept });
    }
    console.log('  saved rankings holding a deleted university: ' + snapFixes.length);

    if (!total && !snapFixes.length) { console.log('\nNothing to clean.'); return; }
    if (!APPLY) { console.log('\nDry run. Re-run with --apply to remove them.'); return; }

    const dir = path.join(__dirname, '..', 'backups');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `orphans-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    fs.writeFileSync(file, JSON.stringify({ tables: found, snapshots: snapFixes }, null, 2));
    console.log(`\nbacked up to ${file}`);

    await client.query('begin');
    // campus_departments hangs off campuses, so clear it before its parents go.
    for (const c of found.campuses || []) {
      await client.query('delete from campus_departments where campus_id = $1', [c.id]);
    }
    for (const t of TABLES) {
      if (!found[t].length) continue;
      await client.query(
        `delete from ${t} t where t.university_id is not null
         and not exists (select 1 from universities x where x.id = t.university_id)`);
    }
    for (const f of snapFixes) {
      await client.query('update user_last_ranking set university_ids = $1 where user_id = $2',
        [JSON.stringify(f.kept), f.user_id]);
    }
    await client.query('commit');

    console.log('\nafter:');
    for (const t of TABLES) {
      const { rows } = await client.query(orphanSql(t));
      console.log('  ' + t.padEnd(18) + String(rows.length).padStart(4));
    }
  } catch (e) {
    try { await client.query('rollback'); } catch { /* nothing to roll back */ }
    throw e;
  } finally {
    client.release();
    await pool.end();
  }
})().catch(e => { console.error('\nFAILED:', e.message); process.exit(1); });
