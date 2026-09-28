import ratelimit, { authRatelimit } from '../config/upstash';
import { verifyAccessToken } from '../utils/jwt';
import type { Request, Response, NextFunction } from 'express';

/**
 * Client IP derived from Express (`req.ip`), which honours the `trust proxy`
 * setting configured in server.ts. We deliberately do NOT read
 * `X-Forwarded-For` directly — trusting that header unconditionally let any
 * client spoof a fresh rate-limit bucket per request.
 */
function clientIp(req: Request): string {
  return req.ip || req.socket?.remoteAddress || 'unknown';
}

/**
 * The bucket a request counts against.
 *
 * Previously this was ALWAYS the IP. That is the wrong unit for a mobile app:
 * a household, an office, a campus or a café all share one public IP behind
 * NAT, so five phones on the same Wi-Fi shared a single 20-requests-per-minute
 * allowance. One person opening the app (which fans out to profile, wallets,
 * transactions, budgets, goals, groups, categories, notifications…) exhausted
 * it on their own, and everyone else on that network started getting 429s that
 * surface in the UI as "connection lost". It is the most likely single cause
 * of the many-devices-at-once failure.
 *
 * So: authenticated traffic is bucketed per USER, which is the unit we
 * actually want to protect, and only anonymous traffic falls back to the IP.
 * The token is properly verified (a cheap HMAC, no DB round-trip) so the
 * bucket can't be spoofed by sending someone else's user id.
 */
function limitKey(req: Request): string {
  const auth = req.headers.authorization || '';
  const [scheme, token] = auth.split(' ');
  if (scheme === 'Bearer' && token) {
    try {
      const user = verifyAccessToken(token);
      return `u:${user.id}`;
    } catch {
      // Expired or forged → fall through to the IP bucket.
    }
  }
  return `ip:${clientIp(req)}`;
}

/** Endpoints that must never be throttled (platform health probes). */
const EXEMPT_PATHS = new Set(['/health']);

/**
 * Global limiter. Fails OPEN on limiter/Redis errors so a cache outage does not
 * take the whole API down; sensitive routes are additionally guarded by
 * `authRateLimiter`, which fails closed.
 */
const rateLimiter = async (req: Request, res: Response, next: NextFunction) => {
  if (EXEMPT_PATHS.has(req.path)) return next();
  try {
    const { success, limit, remaining, reset } = await ratelimit.limit(limitKey(req));
    if (!success) {
      // Tell the client how long to wait instead of leaving it to guess — the
      // app can then back off cleanly rather than hammering and looking offline.
      const retryAfter = Math.max(1, Math.ceil((reset - Date.now()) / 1000));
      res.setHeader('Retry-After', String(retryAfter));
      res.setHeader('RateLimit-Limit', String(limit));
      res.setHeader('RateLimit-Remaining', String(Math.max(0, remaining)));
      res.setHeader('RateLimit-Reset', String(retryAfter));
      return res.status(429).json({
        message: 'Too many requests, please try again in a moment.',
        retryable: true,
        retryAfter,
      });
    }
    return next();
  } catch (error) {
    console.error('[RateLimiter] Error:', error);
    return next();
  }
};

/**
 * Stricter limiter for credential/OTP endpoints. Fails CLOSED — if the limiter
 * is unavailable we reject rather than allow unbounded brute-force attempts.
 *
 * Deliberately still keyed by IP: these are the pre-authentication endpoints,
 * so there is no trustworthy user identity to bucket by, and IP is the control
 * that actually limits credential stuffing. The per-account lockout in
 * upstash.ts is what protects a single account behind a shared NAT.
 */
export const authRateLimiter = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { success, reset } = await authRatelimit.limit(clientIp(req));
    if (!success) {
      const retryAfter = Math.max(1, Math.ceil((reset - Date.now()) / 1000));
      res.setHeader('Retry-After', String(retryAfter));
      return res
        .status(429)
        .json({ message: 'Too many attempts, please try again later.', retryAfter });
    }
    return next();
  } catch (error) {
    console.error('[AuthRateLimiter] Error:', error);
    return res
      .status(503)
      .json({ message: 'Service temporarily unavailable. Please try again later.' });
  }
};

export default rateLimiter;
