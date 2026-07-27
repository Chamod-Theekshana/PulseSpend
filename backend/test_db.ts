import { ChatModel } from './src/models/ChatModel';
import { sql } from './src/config/db';

async function test() {
  try {
    const res = await ChatModel.sendMessage(1, 'test', 'hello world');
    console.log('Success:', res);
  } catch (e) {
    console.error('Error:', e);
  }
  process.exit();
}

test();
