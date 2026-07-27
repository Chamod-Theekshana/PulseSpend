/**
 * Startup environment validation.
 *
 * Fails fast with a clear message when a required secret is missing, instead of
 * booting "successfully" and then throwing on the first authenticated request
 * (the previous behaviour, where `JWT_SECRET` was only checked lazily).
 */

const REQUIRED = ['JWT_SECRET', 'DATABASE_URL'] as const;

// Feature-gated integrations — missing ones only disable a feature, so we warn
// rather than abort.
const RECOMMENDED = [
  'UPSTASH_REDIS_REST_URL',
  'UPSTASH_REDIS_REST_TOKEN',
  'SMTP_HOST',
  'SMTP_USER',
] as const;

export function validateEnv(): void {
  const missing = REQUIRED.filter((key) => !process.env[key] || !String(process.env[key]).trim());
  if (missing.length > 0) {
    console.error(`[Env] Missing required environment variable(s): ${missing.join(', ')}`);
    console.error('[Env] Set them in your .env file (see .env.example) and restart.');
    process.exit(1);
  }

  if (String(process.env.JWT_SECRET).length < 32) {
    console.error('[Env] JWT_SECRET must be at least 32 characters. Refusing to start.');
    process.exit(1);
  }

  const missingRecommended = RECOMMENDED.filter((key) => !process.env[key]);
  if (missingRecommended.length > 0) {
    console.warn(
      `[Env] Optional variable(s) not set (related features disabled): ${missingRecommended.join(', ')}`,
    );
  }
}
