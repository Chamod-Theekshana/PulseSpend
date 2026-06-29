const { neon } = require('@neondatabase/serverless');
require('dotenv/config');
const sql = neon(process.env.DATABASE_URL);

(async () => {
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  console.log('Server local today:', today);

  const r = await sql`SELECT id, title, next_run, is_active FROM recurring_transactions`;
  console.log('All recurring rules:', JSON.stringify(r, null, 2));

  const due = await sql`SELECT id, title, next_run FROM recurring_transactions WHERE is_active = true AND next_run <= ${today}::date`;
  console.log('Due rules:', JSON.stringify(due, null, 2));
})();
