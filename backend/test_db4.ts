import { sql } from './src/config/db';
async function test() {
  const messages = await sql`SELECT * FROM group_messages`;
  console.log('Messages count:', messages.length);
  if (messages.length > 0) console.log('Last message:', messages[messages.length - 1]);
  process.exit();
}
test();
