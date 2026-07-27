import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    globals: false,
    // *.db.test.ts run real statements against Postgres over HTTP, so a handful
    // of round trips per test. They skip themselves without a DATABASE_URL; the
    // pure suites never come near this.
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
