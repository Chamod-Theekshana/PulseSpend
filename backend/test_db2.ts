import { sql } from './src/config/db';
async function test() {
  const users = await sql`SELECT id, email, token_version FROM users LIMIT 1`;
  console.log(users);
  
  const groups = await sql`SELECT * FROM group_members WHERE user_id = ${users[0].id}`;
  console.log('groups:', groups);
  process.exit();
}
test();
