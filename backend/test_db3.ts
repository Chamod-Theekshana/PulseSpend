import { sql } from './src/config/db';
async function test() {
  await sql`INSERT INTO groups (id, name, owner_id, invite_code) VALUES (1, 'Test Group', '2', 'ABCDEF') ON CONFLICT DO NOTHING`;
  await sql`INSERT INTO group_members (group_id, user_id, role) VALUES (1, '2', 'owner') ON CONFLICT DO NOTHING`;
  process.exit();
}
test();
