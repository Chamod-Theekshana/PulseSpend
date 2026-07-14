import ratelimit, { authRatelimit } from '../config/upstash';
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
 * Global limiter. Fails OPEN on limiter/Redis errors so a cache outage does not
 * take the whole API down; sensitive routes are additionally guarded by
 * `authRateLimiter`, which fails closed.
 */
const rateLimiter = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { success } = await ratelimit.limit(clientIp(req));
    if (!success) {
      return res.status(429).json({ message: 'Too many requests, please try again later.' });
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
 */
export const authRateLimiter = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { success } = await authRatelimit.limit(clientIp(req));
    if (!success) {
      return res.status(429).json({ message: 'Too many attempts, please try again later.' });
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
