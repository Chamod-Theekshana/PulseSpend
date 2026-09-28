import cron from 'node-cron';
import { sql } from '../config/db';
import {
  localDayOfMonth,
  localISODate,
  localHour,
  localWeekday,
  type UserZone,
} from '../utils/time';

/**
 * Timezone-aware replacement for `cron.schedule('0 9 * * *', …)`.
 *
 * The old pattern fired once per day in the *server's* zone, which on Render is
 * UTC. A reminder documented as "9 AM" therefore arrived at 14:30 in Colombo,
 * 04:00 in New York and 18:00 in Auckland — the bug report that started this.
 *
 * The fix inverts the loop: instead of one global daily tick, the cron runs
 * **hourly**, and each tick asks "which users is it 9 AM for right now?" Every
 * user gets the job in their own morning, and the job body receives that user's
 * local calendar date so the SQL it runs is anchored correctly too.
 *
 * Two properties worth being explicit about:
 *
 * * **Half-hour and quarter-hour zones work.** India (+05:30), Nepal (+05:45)
 *   and Chatham (+12:45) match on the *hour field*, not on elapsed minutes, so
 *   they fire exactly once per day — just at :00 past their local hour.
 *
 * * **Jobs are idempotent per local day.** A user who flies Tokyo → London can
 *   legitimately pass "it is 9 AM for them" twice in one UTC day. Every run is
 *   therefore keyed on `userId + their local date`, and a repeat key is skipped.
 */

export interface ZonedUser extends UserZone {
  id: string;
  timezone: string | null;
  tz_offset_minutes: number | null;
}

/** `${jobName}:${userId}:${localDate}` for runs already completed. */
const completedRuns = new Set<string>();

/** Keeps [completedRuns] from growing without bound over a long uptime. */
function rememberRun(key: string): void {
  completedRuns.add(key);
  if (completedRuns.size > 50_000) {
    // Cheap eviction: the set is only a same-day guard, so dropping the oldest
    // half costs at worst a duplicate notification for a user mid-flight.
    let dropped = 0;
    for (const k of completedRuns) {
      completedRuns.delete(k);
      if (++dropped >= 25_000) break;
    }
  }
}

/**
 * All users with a push token, plus their zone columns.
 *
 * Restricted to users who could actually receive the notification, so a large
 * dormant account table doesn't cost a full scan every hour.
 */
export async function loadZonedUsers(): Promise<ZonedUser[]> {
  const rows = await sql`
    SELECT DISTINCT u.id::text AS id, u.timezone, u.tz_offset_minutes
    FROM users u
    JOIN user_fcm_tokens t ON t.user_id = u.id::text
    WHERE u.deletion_requested_at IS NULL
  `;
  return rows as ZonedUser[];
}

type Handler = (user: ZonedUser, localDate: string) => Promise<void>;

interface Recurrence {
  /** Local hour 0–23 the job should land on. */
  hour: number;
  /** 0 = Sunday. Omit for a daily job. */
  weekday?: number;
  /** 1–31. Omit for a daily job. Days past a month's end simply never match. */
  dayOfMonth?: number;
}

async function runTick(name: string, rec: Recurrence, handler: Handler): Promise<void> {
  let users: ZonedUser[];
  try {
    users = await loadZonedUsers();
  } catch (err) {
    console.error(`[${name}] Failed to load users for tick:`, err);
    return;
  }

  const now = new Date();
  let sent = 0;

  for (const user of users) {
    try {
      if (localHour(user, now) !== rec.hour) continue;
      if (rec.weekday !== undefined && localWeekday(user, now) !== rec.weekday) continue;
      if (rec.dayOfMonth !== undefined && localDayOfMonth(user, now) !== rec.dayOfMonth) continue;

      const localDate = localISODate(user, now);
      const key = `${name}:${user.id}:${localDate}`;
      if (completedRuns.has(key)) continue;

      // Marked before the handler runs, not after: a handler that throws
      // halfway through has already sent some notifications, and retrying the
      // whole thing an hour later would duplicate them. Failures are logged and
      // picked up on the next natural occurrence.
      rememberRun(key);
      await handler(user, localDate);
      sent++;
    } catch (err) {
      console.error(`[${name}] Failed for user ${user.id}:`, err);
    }
  }

  if (sent > 0) console.log(`[${name}] Ran for ${sent} user(s) in their local ${rec.hour}:00`);
}

function schedule(name: string, rec: Recurrence, handler: Handler): void {
  // Hourly, on the hour. The per-user filtering above is what turns this into
  // "once a day, in each user's own morning".
  cron.schedule('0 * * * *', () => {
    void runTick(name, rec, handler);
  });

  const shape =
    rec.dayOfMonth !== undefined
      ? `day ${rec.dayOfMonth} of each month`
      : rec.weekday !== undefined
        ? `weekday ${rec.weekday}`
        : 'daily';
  console.log(`[${name}] Scheduled ${shape} at ${rec.hour}:00 in each user's local timezone`);
}

/** Runs `handler` once per day, at `hour` in each user's own zone. */
export function scheduleDailyPerUser(name: string, hour: number, handler: Handler): void {
  schedule(name, { hour }, handler);
}

/** Runs `handler` once per week, on `weekday` (0 = Sunday) at local `hour`. */
export function scheduleWeeklyPerUser(
  name: string,
  weekday: number,
  hour: number,
  handler: Handler
): void {
  schedule(name, { hour, weekday }, handler);
}

/** Runs `handler` once per month, on `dayOfMonth` at local `hour`. */
export function scheduleMonthlyPerUser(
  name: string,
  dayOfMonth: number,
  hour: number,
  handler: Handler
): void {
  schedule(name, { hour, dayOfMonth }, handler);
}

/** Test/ops hook: force a tick immediately rather than waiting for the hour. */
export async function runNowForTesting(
  name: string,
  rec: Recurrence,
  handler: Handler
): Promise<void> {
  await runTick(name, rec, handler);
}
