import { neon } from '@neondatabase/serverless';
import 'dotenv/config';

const sql = neon(process.env.DATABASE_URL!);

(async () => {
  // Check raw comparison
  const test1 = await sql`SELECT '2026-03-01'::date <= '2026-03-01'::date as result`;
  console.log('Direct date compare:', test1);

  // Check with the actual next_run values
  const test2 = await sql`
    SELECT id, title, next_run,
           next_run::text as next_run_text,
           '2026-03-01'::date as compare_date,
           (next_run <= '2026-03-01'::date) as is_due_direct,
           (next_run::date <= '2026-03-01'::date) as is_due_cast
    FROM recurring_transactions
  `;
  console.log('Comparison results:', JSON.stringify(test2, null, 2));
})();
