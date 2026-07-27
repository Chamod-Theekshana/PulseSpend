import { describe, it, expect } from 'vitest';
import { detectSubscriptions, normalizeTitle, type TxRow } from './subscriptionDetector';

const DAY = 24 * 60 * 60 * 1000;
// Fixed "now" so recency windows are deterministic.
const NOW = new Date('2026-07-01T00:00:00Z').getTime();

/** Build a series of `count` expenses `gapDays` apart, ending `endAgoDays` before NOW. */
function series(title: string, amount: number, count: number, gapDays: number, endAgoDays: number): TxRow[] {
  const rows: TxRow[] = [];
  const lastMs = NOW - endAgoDays * DAY;
  for (let i = 0; i < count; i++) {
    const ms = lastMs - (count - 1 - i) * gapDays * DAY;
    rows.push({ title, amount, currency: 'LKR', created_at: new Date(ms).toISOString() });
  }
  return rows;
}

describe('normalizeTitle', () => {
  it('strips digits and punctuation, lowercases', () => {
    expect(normalizeTitle('Netflix #12 (2026)')).toBe('netflix');
  });
});

describe('detectSubscriptions cadence buckets', () => {
  it('detects a monthly subscription (>=3 charges, ~30d gaps)', () => {
    const out = detectSubscriptions(series('Netflix', -1500, 3, 30, 5), NOW);
    expect(out).toHaveLength(1);
    expect(out[0].cadenceLabel).toBe('monthly');
    expect(out[0].occurrences).toBe(3);
    expect(out[0].seriesKey).toBe('netflix');
  });

  it('detects a weekly subscription (~7d gaps)', () => {
    const out = detectSubscriptions(series('Gym', -800, 4, 7, 2), NOW);
    expect(out).toHaveLength(1);
    expect(out[0].cadenceLabel).toBe('weekly');
  });

  it('detects a yearly subscription with just 2 charges (~365d gap)', () => {
    const out = detectSubscriptions(series('Domain', -3000, 2, 365, 10), NOW);
    expect(out).toHaveLength(1);
    expect(out[0].cadenceLabel).toBe('yearly');
    expect(out[0].occurrences).toBe(2);
  });

  it('ignores irregular gaps that match no cadence', () => {
    const rows: TxRow[] = [
      { title: 'Random', amount: -100, currency: 'LKR', created_at: new Date(NOW - 100 * DAY).toISOString() },
      { title: 'Random', amount: -100, currency: 'LKR', created_at: new Date(NOW - 85 * DAY).toISOString() },
      { title: 'Random', amount: -100, currency: 'LKR', created_at: new Date(NOW - 2 * DAY).toISOString() },
    ];
    expect(detectSubscriptions(rows, NOW)).toHaveLength(0);
  });

  it('needs >=3 occurrences for monthly (2 is not enough)', () => {
    expect(detectSubscriptions(series('Spotify', -600, 2, 30, 5), NOW)).toHaveLength(0);
  });

  it('drops a stale monthly series whose last charge is long past (cancelled)', () => {
    // 3 monthly charges but the last was ~60 days ago (> 45d recency window).
    expect(detectSubscriptions(series('OldSub', -500, 3, 30, 60), NOW)).toHaveLength(0);
  });

  it('ignores income and short keys', () => {
    const income = series('Salary', 50000, 3, 30, 5);
    expect(detectSubscriptions(income, NOW)).toHaveLength(0);
    const shortKey = series('AB', -100, 3, 30, 5); // key "ab" < 3 chars
    expect(detectSubscriptions(shortKey, NOW)).toHaveLength(0);
  });

  it('computes the price change vs the previous charge', () => {
    const rows = [
      ...series('Netflix', -1500, 2, 30, 35), // older two at 1500
      { title: 'Netflix', amount: -1800, currency: 'LKR', created_at: new Date(NOW - 5 * DAY).toISOString() },
    ];
    const out = detectSubscriptions(rows, NOW);
    expect(out).toHaveLength(1);
    expect(out[0].lastAmount).toBe(1800);
    expect(out[0].previousAmount).toBe(1500);
    expect(out[0].changePct).toBe(20);
  });
});
