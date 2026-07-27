/**
 * In-memory cache for token versions to avoid hitting the database on every authenticated request.
 * TTL is 60 seconds.
 */
interface CacheEntry {
  version: number;
  fetchedAt: number;
}

const TTL_MS = 60 * 1000; // 60 seconds
const cache = new Map<string, CacheEntry>();

export const TokenVersionCache = {
  get: (userId: string): number | null => {
    const entry = cache.get(userId);
    if (entry && Date.now() - entry.fetchedAt < TTL_MS) {
      return entry.version;
    }
    return null; // Cache miss or expired
  },

  set: (userId: string, version: number): void => {
    cache.set(userId, {
      version,
      fetchedAt: Date.now(),
    });
  },

  invalidate: (userId: string): void => {
    cache.delete(userId);
  },
};
