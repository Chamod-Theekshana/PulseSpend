import cron from 'node-cron';
import { sql } from '../config/db';
import { sendPushToUser } from './pushService';
import { withRetries } from './retry';

export interface TxRow {
  title: string;
  amount: number; // signed; expenses negative
  currency: string;
  created_at: string | Date;
}

export type CadenceLabel = 'weekly' | 'monthly' | 'yearly';

export interface DetectedSubscription {
  name: string;
  seriesKey: string; // normalized key, used to dismiss/hide the series
  occurrences: number;
  cadenceDays: number;
  cadenceLabel: CadenceLabel;
  lastAmount: number;
  previousAmount: number;
  changePct: number; // latest vs previous occurrence, in %
  currency: string;
  lastDate: string; // yyyy-MM-dd
}

/** Normalizes a title into a series key: lowercase, digits/dates stripped. */
export function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/\d+/g, '')
    .replace(/[^a-z ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Buckets a median inter-charge gap into a cadence. Each cadence sets its own
 * minimum occurrences and recency window so we only surface subscriptions that
 * still look active (a cancelled monthly sub goes stale after ~45 days; a
 * yearly one is expected to be silent for up to ~13 months).
 */
function classifyCadence(
  median: number,
): { label: CadenceLabel; minOccurrences: number; recencyDays: number } | null {
  if (median >= 5 && median <= 9) return { label: 'weekly', minOccurrences: 3, recencyDays: 14 };
  if (median >= 25 && median <= 35) return { label: 'monthly', minOccurrences: 3, recencyDays: 45 };
  if (median >= 350 && median <= 380) return { label: 'yearly', minOccurrences: 2, recencyDays: 400 };
  return null;
}

/**
 * Pure detection over a user's expense history: same-title expense series with
 * a stable weekly / monthly / yearly cadence are treated as subscriptions. This
 * intentionally analyses REAL transactions — the app's own recurring engine
 * emits fixed amounts, so price changes can only be seen in actual history.
 * `nowMs` is injectable for deterministic tests.
 */
export function detectSubscriptions(rows: TxRow[], nowMs: number = Date.now()): DetectedSubscription[] {
  const series = new Map<string, TxRow[]>();
  for (const row of rows) {
    if (row.amount >= 0) continue; // subscriptions are expenses
    const key = normalizeTitle(row.title);
    if (key.length < 3) continue;
    series.set(key, [...(series.get(key) ?? []), row]);
  }

  const out: DetectedSubscription[] = [];
  for (const [key, txs] of series) {
    if (txs.length < 2) continue; // need ≥1 gap
    const sorted = [...txs].sort(
      (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
    );

    const gaps: number[] = [];
    for (let i = 1; i < sorted.length; i++) {
      gaps.push(
        (new Date(sorted[i].created_at).getTime() - new Date(sorted[i - 1].created_at).getTime()) /
          (24 * 60 * 60 * 1000),
      );
    }
    gaps.sort((a, b) => a - b);
    const median = gaps[Math.floor(gaps.length / 2)];

    const cadence = classifyCadence(median);
    if (!cadence) continue;
    if (sorted.length < cadence.minOccurrences) continue;

    const last = sorted[sorted.length - 1];
    const lastDateObj = new Date(last.created_at);
    // Skip series that have gone quiet — likely cancelled, not active.
    if (nowMs - lastDateObj.getTime() > cadence.recencyDays * 24 * 60 * 60 * 1000) continue;

    const prev = sorted[sorted.length - 2];
    const lastAmount = Math.abs(Number(last.amount));
    const previousAmount = Math.abs(Number(prev.amount));
    const changePct =
      previousAmount > 0 ? ((lastAmount - previousAmount) / previousAmount) * 100 : 0;

    out.push({
      name: last.title,
      seriesKey: key,
      occurrences: sorted.length,
      cadenceDays: Math.round(median),
      cadenceLabel: cadence.label,
      lastAmount: Math.round(lastAmount * 100) / 100,
      previousAmount: Math.round(previousAmount * 100) / 100,
      changePct: Math.round(changePct * 10) / 10,
      currency: last.currency || 'LKR',
      lastDate: `${lastDateObj.getFullYear()}-${String(lastDateObj.getMonth() + 1).padStart(2, '0')}-${String(lastDateObj.getDate()).padStart(2, '0')}`,
    });
  }

  return out.sort((a, b) => b.lastAmount - a.lastAmount);
}

export async function detectForUser(userId: string): Promise<DetectedSubscription[]> {
  // 24-month window so yearly subscriptions (≥2 charges) can be seen; the
  // per-cadence recency guard drops anything that looks cancelled.
  const rows = await sql`
    SELECT title, amount, currency, created_at
    FROM transactions
    WHERE user_id = ${userId} AND deleted_at IS NULL AND amount < 0
      AND transfer_id IS NULL
      AND created_at >= NOW() - INTERVAL '24 months'
    ORDER BY created_at ASC
  `;
  const dismissedRows = await sql`
    SELECT series_key FROM dismissed_subscriptions WHERE user_id = ${userId}
  `;
  const dismissed = new Set(dismissedRows.map((r: any) => String(r.series_key)));
  return detectSubscriptions(rows as unknown as TxRow[]).filter((s) => !dismissed.has(s.seriesKey));
}

/** Hides a detected subscription series (by display name) from future lists. */
export async function dismissSubscription(userId: string, name: string): Promise<void> {
  const key = normalizeTitle(String(name || ''));
  if (key.length < 3) return;
  await sql`
    INSERT INTO dismissed_subscriptions (user_id, series_key)
    VALUES (${userId}, ${key})
    ON CONFLICT (user_id, series_key) DO NOTHING
  `;
}

let isRunning = false;

/**
 * Weekly sweep (Mon 08:30): price-jump alerts (>10% vs the previous charge)
 * for subscriptions whose latest charge landed within the past 7 days — so a
 * given price change alerts exactly once, in the week it happens.
 */
export class SubscriptionDetector {
  static start(): void {
    console.log('[Subscriptions] Scheduling weekly price-change sweep (Mon 08:30)');
    cron.schedule('30 8 * * 1', () => {
      void SubscriptionDetector.run();
    });
  }

  static async run(): Promise<void> {
    if (isRunning) return;
    isRunning = true;
    try {
      const users = await sql`
        SELECT DISTINCT user_id FROM transactions
        WHERE deleted_at IS NULL AND created_at >= NOW() - INTERVAL '40 days'
      `;
      const weekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

      for (const u of users) {
        const userId = String((u as any).user_id);
        try {
          const subs = await detectForUser(userId);
          for (const s of subs) {
            const recent = new Date(s.lastDate).getTime() >= weekAgo;
            if (!recent || s.changePct <= 10) continue;
            await withRetries(
              () => sendPushToUser(
                userId,
                'Subscription price increase 📈',
                `${s.name} went up ${s.changePct}%: ${s.previousAmount.toFixed(2)} → ${s.lastAmount.toFixed(2)} ${s.currency}.`,
                { type: 'subscription_alert', name: s.name },
              ),
              { retries: 1, delayMs: 500 },
            );
          }
        } catch (err) {
          console.error('[Subscriptions] detection failed for user', userId, err);
        }
      }
    } catch (err) {
      console.error('[Subscriptions] sweep failed:', err);
    } finally {
      isRunning = false;
    }
  }
}
