import { Redis } from '@upstash/redis'
import { Ratelimit } from '@upstash/ratelimit'
import "dotenv/config"

const isProd = process.env.NODE_ENV === 'production';

const redis = Redis.fromEnv();

// ── Global limiter ────────────────────────────────────────────────────────────
// Development: 200 req / 60 s — prevents 429 from Flutter hot-reloads & rebuilds.
// Production: 20 req / 60 s per client IP.
const windowRequests = isProd ? 20 : 200;

const ratelimit = new Ratelimit({
  redis: redis,
  limiter: Ratelimit.slidingWindow(windowRequests, "60 s"),
  prefix: "ratelimit",
});

// ── Auth-sensitive limiter ────────────────────────────────────────────────────
// Applied per-IP to credential/OTP endpoints (signin, signup, OTP send/verify).
// Kept loose enough to survive shared NAT; the real brute-force control is the
// per-account lockout below.
const authWindowRequests = isProd ? 20 : 100;

export const authRatelimit = new Ratelimit({
  redis: redis,
  limiter: Ratelimit.slidingWindow(authWindowRequests, "15 m"),
  prefix: "ratelimit:auth",
});

// ── Per-account login-failure lockout ─────────────────────────────────────────
// A token is consumed only on a FAILED sign-in, so legitimate logins are never
// penalised. After this many failures for one email within the window, further
// attempts are temporarily locked out.
export const LOGIN_FAILURE_LIMIT = 5;

export const loginFailRatelimit = new Ratelimit({
  redis: redis,
  limiter: Ratelimit.slidingWindow(LOGIN_FAILURE_LIMIT, "15 m"),
  prefix: "ratelimit:loginfail",
});

export default ratelimit;
