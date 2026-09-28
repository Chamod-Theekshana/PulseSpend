/**
 * Short-TTL cache for "is user X a member of group Y?".
 *
 * Why this exists: every `join_group` and every `send_message` used to run a
 * fresh `SELECT 1 FROM group_members` against Neon. With a few dozen devices
 * reconnecting at once (a deploy, a Wi-Fi flap, a lunchtime group chat) that is
 * a burst of hundreds of round-trips, which saturates the pg pool and makes
 * *every* request — REST included — start timing out. Membership changes rarely,
 * so a 30 s cache removes almost all of that load with no user-visible staleness.
 *
 * Negative results are cached too, but for a much shorter window, so someone who
 * has just been added to a group isn't locked out for the full TTL.
 */
interface Entry {
  isMember: boolean;
  fetchedAt: number;
}

const POSITIVE_TTL_MS = 30 * 1000;
const NEGATIVE_TTL_MS = 5 * 1000;
/** Hard cap so a pathological number of group/user pairs can't grow unbounded. */
const MAX_ENTRIES = 10_000;

const cache = new Map<string, Entry>();

function key(groupId: string | number, userId: string): string {
  return `${groupId}:${userId}`;
}

export const GroupMembershipCache = {
  /** `true`/`false` on a fresh hit, `null` on a miss or expiry. */
  get(groupId: string | number, userId: string): boolean | null {
    const entry = cache.get(key(groupId, userId));
    if (!entry) return null;
    const ttl = entry.isMember ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS;
    if (Date.now() - entry.fetchedAt >= ttl) {
      cache.delete(key(groupId, userId));
      return null;
    }
    return entry.isMember;
  },

  set(groupId: string | number, userId: string, isMember: boolean): void {
    if (cache.size >= MAX_ENTRIES) {
      // Cheapest possible eviction: drop the oldest insertion. Map preserves
      // insertion order, so the first key is the least recently *added*.
      const oldest = cache.keys().next();
      if (!oldest.done) cache.delete(oldest.value);
    }
    cache.set(key(groupId, userId), { isMember, fetchedAt: Date.now() });
  },

  /** Call after add/remove/leave/disband so the change takes effect at once. */
  invalidate(groupId: string | number, userId?: string): void {
    if (userId) {
      cache.delete(key(groupId, userId));
      return;
    }
    const prefix = `${groupId}:`;
    for (const k of cache.keys()) {
      if (k.startsWith(prefix)) cache.delete(k);
    }
  },

  clear(): void {
    cache.clear();
  },
};
