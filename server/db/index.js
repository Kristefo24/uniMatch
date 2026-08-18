// Picks the storage driver from DB_DRIVER (json | mysql | supabase).
const driver = (process.env.DB_DRIVER || 'json').toLowerCase();

let impl;
if (driver === 'mysql') impl = require('./mysql-driver');
else if (driver === 'supabase') impl = require('./supabase-driver');
else impl = require('./json-driver');

console.log(`[db] using "${driver}" driver`);
module.exports = impl;
