import { Redis } from '@upstash/redis'
import { Ratelimit } from '@upstash/ratelimit'
import "dotenv/config"

const isProd = process.env.NODE_ENV === 'production';

export const redis = Redis.fromEnv();

// ── Global limiter ────────────────────────────────────────────────────────────
// Bucketed per authenticated USER (see middleware/RateLimiter.ts), falling back
// to IP for anonymous traffic.
//
// The old production value was 20 req / 60 s per *IP*, which was far below what
// a single legitimate session needs: one cold start fans out to profile,
// wallets, transactions, budgets, goals, categories, notifications, groups,
// analytics and exchange rates — and pull-to-refresh does it again. Any second
// device on the same Wi-Fi then got nothing but 429s. 120/min per user is
// generous for a human using the app and still stops a runaway client.
const windowRequests = isProd ? 120 : 600;

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
