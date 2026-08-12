import { sendPushToUser } from './pushService';
import { sql } from '../config/db';
import { withRetries } from './retry';
import { offsetFor } from '../utils/time';

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

/**
 * Milliseconds until the next `hour:minute` **in the user's own timezone**.
 *
 * `next.setHours(...)` sets the hour in the *server's* zone, so this fired at
 * 12:10 UTC for everyone — 17:40 in Colombo. Working in offset-shifted UTC
 * fields keeps the arithmetic in one zone throughout.
 */
async function msUntilNextDailyTime(userId: string, hour: number, minute: number) {
  const rows = await sql`
    SELECT timezone, tz_offset_minutes FROM users WHERE id = ${userId}
  `;
  const zone = (rows[0] as any) ?? {};
  const offset = offsetFor(zone) * 60000;

  const now = new Date();
  // Shift into the user's local frame, pick the next occurrence there, shift back.
  const local = new Date(now.getTime() + offset);
  const next = new Date(local);
  next.setUTCHours(hour, minute, 0, 0);
  if (next <= local) next.setUTCDate(next.getUTCDate() + 1);

  return next.getTime() - local.getTime();
}

async function scheduleDaily(userId: string, hour: number, minute: number) {
  const delay = await msUntilNextDailyTime(userId, hour, minute);

  // (optional) log next run time
  const nextRun = new Date(Date.now() + delay);
  console.log(`[TestNotif] Next daily notification for user ${userId} at ${nextRun.toString()}`);

  const timeout = setTimeout(async () => {
    try {
      await withRetries(() => sendTestNotification(userId), { retries: 1, delayMs: 500 });
    } catch (err) {
      console.error('[TestNotif] Error in daily send:', err);
    } finally {
      // Schedule again for the next day. Re-resolving the offset each time
      // means a DST change (or the user flying) is picked up automatically.
      void scheduleDaily(userId, hour, minute);
    }
  }, delay);

  activeTimeouts.set(userId, timeout);
}

export async function startTestNotifications(userId: string) {
  const uid = String(userId);

  // Stop any existing scheduled job for this user
  stopTestNotifications(uid);

  console.log(`[TestNotif] Starting DAILY test notifications for user ${uid} at 12:10 local time`);

  // If you DO NOT want an immediate send, remove the next line.
  // await sendTestNotification(uid);

  await scheduleDaily(uid, 12, 10);
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