import { Redis } from '@upstash/redis'
import { Ratelimit } from '@upstash/ratelimit'
import "dotenv/config"

const redis = Redis.fromEnv();

// Development: 200 req / 60 s — prevents 429 from Flutter hot-reloads & widget rebuilds
// Production: tighten this back to 20–50 req / 60 s per IP
const windowRequests = process.env.NODE_ENV === 'production' ? 20 : 200;

const ratelimit = new Ratelimit({
  redis: redis,
  limiter: Ratelimit.slidingWindow(windowRequests, "60s"),
  prefix: "ratelimit",
});

export default ratelimit ;