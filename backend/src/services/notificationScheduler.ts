import { sendPushToUser } from './pushService';
import { sql } from '../config/db';
import { withRetries } from './retry';

// Map of userId -> timeout timer (daily schedule)
const activeTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

async function getUserName(userId: string): Promise<string> {
  try {
    const rows = await sql`SELECT name FROM users WHERE id = ${userId}`;
    const name = rows[0]?.name;
    return name && name.trim() ? name.trim() : 'there';
  } catch (err) {
    console.error('[TestNotif] Failed to fetch user name:', err);
    return 'there';
  }
}

async function sendTestNotification(userId: string) {
  const name = await getUserName(userId);
  const now = new Date().toLocaleTimeString();
  console.log(`[TestNotif] Sending test notification to user ${userId} (${name}) at ${now}`);

  await sendPushToUser(
    userId,
    `Hi ${name}! 👋`,
    `PulseSpend is keeping track of your expenses. (${now})`,
    { type: 'test_daily' }
  );
}

function msUntilNextDailyTime(hour: number, minute: number) {
  const now = new Date();
  const next = new Date(now);

  next.setHours(hour, minute, 0, 0); // today at HH:MM
  if (next <= now) next.setDate(next.getDate() + 1); // if already passed, tomorrow

  return next.getTime() - now.getTime();
}

function scheduleDaily(userId: string, hour: number, minute: number) {
  const delay = msUntilNextDailyTime(hour, minute);

  // (optional) log next run time
  const nextRun = new Date(Date.now() + delay);
  console.log(`[TestNotif] Next daily notification for user ${userId} at ${nextRun.toString()}`);

  const timeout = setTimeout(async () => {
    try {
      await withRetries(() => sendTestNotification(userId), { retries: 1, delayMs: 500 });
    } catch (err) {
      console.error('[TestNotif] Error in daily send:', err);
    } finally {
      // schedule again for next day
      scheduleDaily(userId, hour, minute);
    }
  }, delay);

  activeTimeouts.set(userId, timeout);
}

export async function startTestNotifications(userId: string) {
  const uid = String(userId);

  // Stop any existing scheduled job for this user
  stopTestNotifications(uid);

  console.log(`[TestNotif] Starting DAILY test notifications for user ${uid} at 2:50 PM`);

  // If you DO NOT want an immediate send, remove the next line.
  // await sendTestNotification(uid);

  // Schedule daily at 4:30 PM (16:30)
  scheduleDaily(uid, 12, 10);
}

export function stopTestNotifications(userId: string) {
  const uid = String(userId);
  const existing = activeTimeouts.get(uid);
  if (existing) {
    clearTimeout(existing);
    activeTimeouts.delete(uid);
    console.log(`[TestNotif] Stopped daily test notifications for user ${uid}`);
  }
}