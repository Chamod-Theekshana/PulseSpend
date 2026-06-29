import ratelimit from '../config/upstash';
import type { Request, Response, NextFunction } from 'express';

const rateLimiter = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const forwarded = req.headers['x-forwarded-for'];
    const ip = (
      (Array.isArray(forwarded) ? forwarded[0] : forwarded?.split(',')[0]?.trim()) ||
      req.socket?.remoteAddress ||
      req.ip ||
      'unknown'
    );

    const { success } = await ratelimit.limit(ip);

    if (!success) {
      return res.status(429).json({ message: 'Too many requests, please try again later.' });
    }

    return next();
  } catch (error) {
    // On rate limiter failure (e.g., Redis unavailable), allow request through
    console.error('[RateLimiter] Error:', error);
    return next();
  }
};

export default rateLimiter;
