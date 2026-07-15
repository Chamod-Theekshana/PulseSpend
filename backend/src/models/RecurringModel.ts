import { sql } from '../config/db';

export type RecurringRow = {
  id: number;
  user_id: string;
  title: string;
  amount: number;
  currency?: string;
  category: string;
  frequency: string;
  next_run: string;
  is_active: boolean;
  wallet_id?: number | null;
  created_at: string;
};

// NOTE: every SELECT below includes currency + wallet_id — omitting `currency`
// was the root cause of recurring charges always posting in LKR.
export class RecurringModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<RecurringRow[]> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
      FROM recurring_transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY next_run ASC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as RecurringRow[];
  }

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM recurring_transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async findById(userId: string, id: number): Promise<RecurringRow | null> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
      FROM recurring_transactions
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as RecurringRow) || null;
  }

  static async create(
    userId: string,
    title: string,
    amount: number,
    category: string,
    frequency: string,
    nextRun: string,
    currency: string = 'LKR',
    walletId: number | null = null,
  ): Promise<RecurringRow> {
    const wallet = walletId && walletId > 0 ? walletId : null;
    const rows = await sql`
      INSERT INTO recurring_transactions (user_id, title, amount, currency, category, frequency, next_run, wallet_id)
      VALUES (${userId}, ${title}, ${amount}, ${currency}, ${category}, ${frequency}, ${nextRun}::date, ${wallet})
      RETURNING id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
    `;
    return rows[0] as RecurringRow;
  }

  static async update(
    userId: string,
    id: number,
    fields: {
      title?: string;
      amount?: number;
      currency?: string;
      category?: string;
      frequency?: string;
      is_active?: boolean;
      wallet_id?: number | null;
      next_run?: string;
    }
  ): Promise<RecurringRow | null> {
    // wallet_id needs to distinguish "unchanged" (undefined) from "clear to
    // default" (null), so COALESCE won't do — apply it only when provided.
    const walletProvided = fields.wallet_id !== undefined;
    const wallet = fields.wallet_id && fields.wallet_id > 0 ? fields.wallet_id : null;
    const rows = await sql`
      UPDATE recurring_transactions
      SET
        title = COALESCE(${fields.title ?? null}, title),
        amount = COALESCE(${fields.amount ?? null}, amount),
        currency = COALESCE(${fields.currency ?? null}, currency),
        category = COALESCE(${fields.category ?? null}, category),
        frequency = COALESCE(${fields.frequency ?? null}, frequency),
        is_active = COALESCE(${fields.is_active ?? null}, is_active),
        next_run = COALESCE(${fields.next_run ?? null}::date, next_run),
        wallet_id = CASE WHEN ${walletProvided} THEN ${wallet} ELSE wallet_id END
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
    `;
    return (rows[0] as RecurringRow) || null;
  }

  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE recurring_transactions
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    return rows.length > 0;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    if (ids.length === 0) return 0;
    const rows = await sql`
      UPDATE recurring_transactions
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }

  /**
   * Get all active recurrences that are due (next_run <= today).
   */
  static async getDueRecurrences(): Promise<RecurringRow[]> {
    // Use server local date (not UTC)
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    console.log('[Recurring] Checking due recurrences for local date:', today);
    // Use AT TIME ZONE 'UTC' to strip Neon's timezone offset on DATE columns
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
      FROM recurring_transactions
      WHERE is_active = true
        AND deleted_at IS NULL
        AND (next_run AT TIME ZONE 'UTC')::date <= ${today}::date
      ORDER BY next_run ASC
    `;
    return rows as RecurringRow[];
  }

  /**
   * Active rules charging tomorrow that we haven't reminded about today yet
   * (day-before "upcoming charge" reminder, deduped via last_reminded_on).
   */
  static async listDueForReminder(tomorrowISO: string, todayISO: string): Promise<RecurringRow[]> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, frequency, next_run, is_active, wallet_id, created_at
      FROM recurring_transactions
      WHERE is_active = true
        AND deleted_at IS NULL
        AND (next_run AT TIME ZONE 'UTC')::date = ${tomorrowISO}::date
        AND (last_reminded_on IS NULL OR last_reminded_on <> ${todayISO}::date)
    `;
    return rows as RecurringRow[];
  }

  static async markReminded(id: number, todayISO: string): Promise<void> {
    await sql`UPDATE recurring_transactions SET last_reminded_on = ${todayISO}::date WHERE id = ${id}`;
  }

  /**
   * Advance next_run by the frequency interval.
   */
  static async advanceNextRun(id: number, frequency: string): Promise<void> {
    const interval = frequency === 'daily' ? '1 day'
      : frequency === 'weekly' ? '7 days'
      : frequency === 'yearly' ? '1 year'
      : '1 month'; // default monthly

    await sql`
      UPDATE recurring_transactions
      SET next_run = next_run + ${interval}::interval
      WHERE id = ${id}
    `;
  }
}
