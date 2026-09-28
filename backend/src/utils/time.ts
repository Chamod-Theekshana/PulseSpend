/**
 * Timezone helpers.
 *
 * The problem this solves: every scheduler in this codebase used to be written
 * as `cron.schedule('0 9 * * *', …)` — "9 AM". But 9 AM *where*? `node-cron`
 * fires in the host process's zone, and the host is UTC on Render. So a bill
 * reminder advertised as "9 AM" arrived at 14:30 in Colombo, 04:00 in New York
 * and 18:00 in Auckland. The same applies to `new Date().toISOString().slice(0, 10)`,
 * which is the *UTC* date and is therefore a day behind for anyone east of UTC
 * late in the evening (and a day ahead for anyone west of it early in the morning).
 *
 * The fix is not to pick a different fixed zone — it is to stop having one. Each
 * user carries their own zone (`users.timezone`, with `users.tz_offset_minutes`
 * as a fallback), schedulers run every hour, and each run only touches the users
 * for whom it is currently the target local hour.
 *
 * Zone resolution order:
 *   1. `users.timezone` — an IANA id like `Asia/Colombo`. DST-correct, because
 *      `Intl` knows when the rules change.
 *   2. `users.tz_offset_minutes` — a fixed offset the client reports. Correct
 *      except across a DST boundary that falls between two client syncs.
 *   3. UTC.
 */

/** Minutes east of UTC. Colombo = 330, New York in winter = -300. */
export type OffsetMinutes = number;

export interface UserZone {
  timezone?: string | null;
  tz_offset_minutes?: number | string | null;
}

const VALID_ZONE_CACHE = new Map<string, boolean>();

/**
 * True when `Intl` recognises the id. Cached because `updateProfile` would
 * otherwise construct a formatter on every request just to throw it away.
 */
export function isValidTimeZone(zone: string): boolean {
  const cached = VALID_ZONE_CACHE.get(zone);
  if (cached !== undefined) return cached;

  let ok = false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    ok = true;
  } catch {
    ok = false;
  }
  VALID_ZONE_CACHE.set(zone, ok);
  return ok;
}

/**
 * The offset of `zone` at `at`, in minutes east of UTC.
 *
 * Computed by asking `Intl` for the wall-clock fields in that zone and
 * subtracting the UTC instant — this is the standard trick, and unlike a
 * hard-coded table it stays correct across DST transitions and political
 * timezone changes.
 */
export function zoneOffsetMinutes(zone: string, at: Date = new Date()): OffsetMinutes {
  if (!isValidTimeZone(zone)) return 0;

  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(at);

  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? '0');
  // `hour: '2-digit'` with hour12:false yields 24 for midnight in some ICU
  // versions; normalise so the arithmetic below doesn't jump a day.
  const hour = get('hour') % 24;

  const asUtc = Date.UTC(
    get('year'),
    get('month') - 1,
    get('day'),
    hour,
    get('minute'),
    get('second')
  );

  // Round to the minute: `at` carries milliseconds that the formatter dropped.
  return Math.round((asUtc - at.getTime()) / 60000);
}

/** Resolves a user row to an offset, applying the fallback chain above. */
export function offsetFor(user: UserZone, at: Date = new Date()): OffsetMinutes {
  const zone = user.timezone?.trim();
  if (zone && isValidTimeZone(zone)) return zoneOffsetMinutes(zone, at);

  const raw = user.tz_offset_minutes;
  const offset = typeof raw === 'string' ? Number(raw) : raw;
  if (typeof offset === 'number' && Number.isFinite(offset) && Math.abs(offset) <= 900) {
    return Math.round(offset);
  }

  return 0;
}

/**
 * The same instant expressed as a `Date` whose *UTC* fields hold the user's
 * local wall clock. Never send this to the database or serialise it — it is a
 * scratch value for reading `.getUTCHours()`, `.getUTCDay()` and friends.
 */
function asLocalFields(at: Date, offset: OffsetMinutes): Date {
  return new Date(at.getTime() + offset * 60000);
}

/** The user's local hour, 0–23. */
export function localHour(user: UserZone, at: Date = new Date()): number {
  return asLocalFields(at, offsetFor(user, at)).getUTCHours();
}

/** The user's local day of week, 0 = Sunday. */
export function localWeekday(user: UserZone, at: Date = new Date()): number {
  return asLocalFields(at, offsetFor(user, at)).getUTCDay();
}

/** The user's local day of month, 1–31. */
export function localDayOfMonth(user: UserZone, at: Date = new Date()): number {
  return asLocalFields(at, offsetFor(user, at)).getUTCDate();
}

/**
 * The user's local calendar date as `YYYY-MM-DD`.
 *
 * This is the replacement for `new Date().toISOString().slice(0, 10)`, which
 * answers "what is the date in Greenwich" — not a question any user has ever
 * asked.
 */
export function localISODate(user: UserZone, at: Date = new Date()): string {
  return toISODateUTC(asLocalFields(at, offsetFor(user, at)));
}

/** `YYYY-MM-DD` from a Date's UTC fields. */
export function toISODateUTC(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(
    d.getUTCDate()
  ).padStart(2, '0')}`;
}

/** `YYYY-MM-DD` from a Date's *host process* fields. Prefer [localISODate]. */
export function toISODateHost(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`;
}

/** The user's local date shifted by `days`, as `YYYY-MM-DD`. */
export function localISODateOffset(
  user: UserZone,
  days: number,
  at: Date = new Date()
): string {
  const shifted = asLocalFields(at, offsetFor(user, at));
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return toISODateUTC(shifted);
}

/**
 * Whether it is currently `targetHour` o'clock for this user.
 *
 * Schedulers call this once per hourly tick. Zones offset by 30 or 45 minutes
 * (India, Nepal, Chatham Islands) still match exactly once per day, because the
 * comparison is on the hour field rather than on elapsed minutes.
 */
export function isLocalHour(
  user: UserZone,
  targetHour: number,
  at: Date = new Date()
): boolean {
  return localHour(user, at) === targetHour;
}

/**
 * Guards against a job double-firing for one user. A user who flies from Tokyo
 * to London can pass `isLocalHour(9)` twice in one calendar day; pairing the
 * hour check with a `last_*_on` column keyed to [localISODate] makes each job
 * idempotent per local day. Callers own that column; this is the key to use.
 */
export function localRunKey(user: UserZone, at: Date = new Date()): string {
  return localISODate(user, at);
}

/** Normalises a client-supplied offset, rejecting nonsense. Range is ±15h. */
export function sanitizeOffsetMinutes(value: unknown): number | null {
  const n = typeof value === 'string' ? Number(value) : value;
  if (typeof n !== 'number' || !Number.isFinite(n)) return null;
  const rounded = Math.round(n);
  if (Math.abs(rounded) > 900) return null;
  return rounded;
}
