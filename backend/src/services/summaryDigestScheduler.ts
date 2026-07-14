import cron from 'node-cron';
import { sql } from '../config/db';
import { AnalyticsModel, DigestSummary } from '../models/AnalyticsModel';
import { sendPushToUser } from './pushService';
import { emitToUser } from '../socket';
import { withRetries } from './retry';

let isRunning = false;

function money(n: number, currency: string): string {
  return `${Math.round(n).toLocaleString('en-US')} ${currency}`;
}

/** Turns a digest into a friendly push title + body. */
export function buildDigestMessage(d: DigestSummary): { title: string; body: string } {
  const title = d.range === 'week' ? '📊 Your weekly recap' : '📊 Your monthly recap';
  const window = d.range === 'week' ? 'this week' : 'last month';

  const parts: string[] = [
    `You spent ${money(d.expense, d.currency)} and earned ${money(d.income, d.currency)} ${window}.`,
  ];
  if (d.topCategory) {
    parts.push(`Top category: ${d.topCategory.name} (${money(d.topCategory.amount, d.currency)}).`);
  }
  if (d.income > 0) {
    parts.push(`You saved ${Math.round(d.savingsRate)}% of your income.`);
  }
  return { title, body: parts.join(' ') };
}

/**
 * Scheduled spending recaps. Weekly every Monday and monthly on the 1st, both
 * at 08:00 server time. Skips users with no activity in the window, and
 * sendPushToUser already drops the push for anyone who muted the
 * `summary_digest` category — so this stays quiet for opted-out users.
 */
export class SummaryDigestScheduler {
  static start(): void {
    console.log('[Digest] Scheduling weekly (Mon 08:00) and monthly (1st 08:00) recaps');
    cron.schedule('0 8 * * 1', () => {
      void SummaryDigestScheduler.run('week');
    });
    cron.schedule('0 8 1 * *', () => {
      void SummaryDigestScheduler.run('month');
    });
  }

  static async run(range: 'week' | 'month'): Promise<void> {
    if (isRunning) {
      console.warn('[Digest] Previous run still in progress, skipping.');
      return;
    }
    isRunning = true;
    try {
      const users = await sql`SELECT id FROM users`;
      console.log(`[Digest] Building ${range} recaps for ${users.length} user(s)`);

      for (const u of users) {
        const userId = String((u as any).id);
        try {
          const digest = await AnalyticsModel.getDigest(userId, range);
          if (digest.transactionCount === 0) continue; // nothing to report

          const { title, body } = buildDigestMessage(digest);
          await withRetries(
            () => sendPushToUser(userId, title, body, { type: 'summary_digest', range }),
            { retries: 1, delayMs: 500 },
          );
          emitToUser(userId, 'digest:new', { title, body, digest });
        } catch (err) {
          console.error('[Digest] Failed for user', userId, err);
        }
      }
    } catch (err) {
      console.error('[Digest] Run failed:', err);
    } finally {
      isRunning = false;
    }
  }
}
