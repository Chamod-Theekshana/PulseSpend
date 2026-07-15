import { sql } from '../config/db';
import { convert, getRate } from '../services/exchangeRateService';

export type BudgetRow = {
  id: number;
  user_id: string;
  category: string;
  amount: number;
  currency: string;
  period: string;
  created_at: string;
};

export type BudgetStatus = BudgetRow & {
  spent: number;
  percentage: number;
  remaining: number;
  /** true when one or more transaction currencies could not be converted — spent/percentage may be understated */
  conversion_error: boolean;
};

export class BudgetModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<BudgetRow[]> {
    const rows = await sql`
      SELECT id, user_id, category, amount, currency, period, created_at
      FROM budgets
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY category ASC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as BudgetRow[];
  }

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM budgets
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async findById(userId: string, id: number): Promise<BudgetRow | null> {
    const rows = await sql`
      SELECT id, user_id, category, amount, currency, period, created_at
      FROM budgets
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as BudgetRow) || null;
  }

  static async create(
    userId: string,
    category: string,
    amount: number,
    currency: string = 'LKR',
    period: string = 'monthly'
  ): Promise<BudgetRow> {
    const rows = await sql`
      INSERT INTO budgets (user_id, category, amount, currency, period)
      VALUES (${userId}, ${category}, ${amount}, ${currency}, ${period})
      RETURNING id, user_id, category, amount, currency, period, created_at
    `;
    return rows[0] as BudgetRow;
  }

  static async update(userId: string, id: number, amount: number): Promise<BudgetRow | null> {
    const rows = await sql`
      UPDATE budgets
      SET amount = ${amount}
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, category, amount, currency, period, created_at
    `;
    return (rows[0] as BudgetRow) || null;
  }

  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE budgets
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    return rows.length > 0;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    if (ids.length === 0) return 0;
    const rows = await sql`
      UPDATE budgets
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }

  /**
   * Spending per category+currency in [startDate, endDate], accounting for both
   * unsplit transactions and split-category amounts. Returns category → list of
   * { amount, currency }. Extracted so the same aggregation can run over
   * different windows (per-budget periods).
   */
  private static async aggregateSpending(
    userId: string,
    startDate: string,
    endDate: string,
  ): Promise<Map<string, Array<{ amount: number; currency: string }>>> {
    const spendingRows = await sql`
      WITH unsplit_expenses AS (
        SELECT t.category AS category, t.currency AS currency, ABS(SUM(t.amount)) AS total
        FROM transactions t
        WHERE t.user_id = ${userId}
          AND t.amount < 0
          AND t.deleted_at IS NULL
          AND t.created_at >= ${startDate}::date
          AND t.created_at <= ${endDate}::date
          AND NOT EXISTS (
            SELECT 1 FROM transaction_splits s WHERE s.transaction_id = t.id
          )
        GROUP BY t.category, t.currency
      ),
      split_expenses AS (
        SELECT s.category AS category, t.currency AS currency, ABS(SUM(s.amount)) AS total
        FROM transaction_splits s
        INNER JOIN transactions t ON t.id = s.transaction_id
        WHERE s.user_id = ${userId}
          AND t.user_id = ${userId}
          AND s.amount < 0
          AND t.deleted_at IS NULL
          AND t.created_at >= ${startDate}::date
          AND t.created_at <= ${endDate}::date
        GROUP BY s.category, t.currency
      ),
      combined AS (
        SELECT category, currency, total FROM unsplit_expenses
        UNION ALL
        SELECT category, currency, total FROM split_expenses
      )
      SELECT category, currency, SUM(total) AS total
      FROM combined
      GROUP BY category, currency
    `;

    const map = new Map<string, Array<{ amount: number; currency: string }>>();
    for (const row of spendingRows as any[]) {
      const cat = String(row.category);
      if (!map.has(cat)) map.set(cat, []);
      map.get(cat)!.push({ amount: Number(row.total), currency: String(row.currency || 'LKR') });
    }
    return map;
  }

  /** Current-period window (inclusive ISO dates) for a budget period. */
  static periodWindow(period: string, now: Date = new Date()): { startDate: string; endDate: string } {
    const iso = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    if (period === 'weekly') {
      const dow = (now.getDay() + 6) % 7; // 0 = Monday … 6 = Sunday
      const monday = new Date(now);
      monday.setDate(now.getDate() - dow);
      const sunday = new Date(monday);
      sunday.setDate(monday.getDate() + 6);
      return { startDate: iso(monday), endDate: iso(sunday) };
    }
    if (period === 'yearly') {
      return { startDate: `${now.getFullYear()}-01-01`, endDate: `${now.getFullYear()}-12-31` };
    }
    // monthly (default)
    const start = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
    const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const end = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
    return { startDate: start, endDate: end };
  }

  /**
   * Returns all budgets for a user with spending calculated per budget.
   * Default (no date args): each budget's spend is measured over ITS OWN period
   * window (weekly / monthly / yearly). Explicit year[/month[/day]]: a single
   * fixed window applies to every budget (the calendar / heatmap drill-down).
   * Currency conversion is batched per unique currency pair.
   */
  static async getStatusByUser(
    userId: string,
    year?: number,
    month?: number,
    day?: number,
  ): Promise<BudgetStatus[]> {
    const budgets = await sql`
      SELECT id, user_id, category, amount, currency, period, created_at
      FROM budgets
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY category ASC
    `;

    // Resolve each budget's spending array — either from a single explicit
    // window, or from its own period's current window.
    const budgetSpending = new Map<number, Array<{ amount: number; currency: string }>>();

    if (year) {
      let startDate: string;
      let endDate: string;
      if (month && day) {
        startDate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
        endDate = startDate;
      } else if (month) {
        startDate = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay = new Date(year, month, 0).getDate();
        endDate = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;
      } else {
        startDate = `${year}-01-01`;
        endDate = `${year}-12-31`;
      }
      const map = await this.aggregateSpending(userId, startDate, endDate);
      for (const b of budgets as any[]) budgetSpending.set(b.id, map.get(b.category) || []);
    } else {
      // Only query the distinct periods the user actually has budgets for.
      const periodsNeeded = new Set((budgets as any[]).map((b) => String(b.period || 'monthly')));
      const mapByPeriod = new Map<string, Map<string, Array<{ amount: number; currency: string }>>>();
      await Promise.all(
        Array.from(periodsNeeded).map(async (p) => {
          const w = this.periodWindow(p);
          mapByPeriod.set(p, await this.aggregateSpending(userId, w.startDate, w.endDate));
        }),
      );
      for (const b of budgets as any[]) {
        const map = mapByPeriod.get(String(b.period || 'monthly'))!;
        budgetSpending.set(b.id, map.get(b.category) || []);
      }
    }

    // Pre-fetch unique currency pairs needed (avoid redundant convert() calls)
    // null = conversion failed (rate unavailable) — surfaces so UI can warn
    const conversionCache = new Map<string, number | null>();
    const uniquePairs = new Set<string>();
    for (const budget of budgets as any[]) {
      const budgetCurrency = String(budget.currency || 'LKR');
      const rows = budgetSpending.get(budget.id) || [];
      for (const row of rows) {
        if (row.currency !== budgetCurrency) {
          uniquePairs.add(`${row.currency}→${budgetCurrency}`);
        }
      }
    }

    // Fetch all needed rates in parallel
    await Promise.all(
      Array.from(uniquePairs).map(async (pair) => {
        const [from, to] = pair.split('→');
        try {
          const rate = await getRate(from, to);
          conversionCache.set(pair, rate);
        } catch {
          // Store null — NOT 1. Rate=1 would silently show wrong data (e.g. $50 displayed as LKR 50).
          // null lets the caller decide how to surface the conversion failure.
          conversionCache.set(pair, null);
          console.warn(`[BudgetModel] Rate unavailable for ${from}→${to}. Budget spent will be marked as unconvertible.`);
        }
      })
    );

    // Now calculate statuses without any additional async calls
    return (budgets as any[]).map((b) => {
      const budgetCurrency = String(b.currency || 'LKR');
      const amountVal = Number(b.amount);
      const spending = budgetSpending.get(b.id) || [];

      let spentTotal = 0;
      let hasConversionError = false;

      for (const s of spending) {
        if (s.currency === budgetCurrency) {
          spentTotal += s.amount;
        } else {
          const rate = conversionCache.get(`${s.currency}→${budgetCurrency}`);
          if (rate === null || rate === undefined) {
            // Rate unavailable — flag it so client can show a warning
            hasConversionError = true;
          } else {
            spentTotal += s.amount * rate;
          }
        }
      }

      const spent = Math.round(spentTotal * 100) / 100;
      const percentage = amountVal > 0 ? Math.round((spent / amountVal) * 100) : 0;
      const remaining = Math.max(0, Math.round((amountVal - spent) * 100) / 100);

      return {
        id: b.id,
        user_id: b.user_id,
        category: b.category,
        amount: amountVal,
        currency: budgetCurrency,
        period: b.period,
        created_at: b.created_at,
        spent,
        percentage,
        remaining,
        conversion_error: hasConversionError,
      };
    });
  }

  /** Sets (or clears, when null) the user's overall monthly budget cap. */
  static async setTotalBudget(userId: string, amount: number | null): Promise<void> {
    await sql`UPDATE users SET total_budget = ${amount} WHERE id = ${userId}`;
  }

  /**
   * Overall spend for the current month vs the user's total_budget cap, in the
   * user's preferred currency. Transfers are excluded (they aren't spending).
   * Returns amount = null when no total budget is set.
   */
  static async getTotalStatus(userId: string): Promise<{
    amount: number | null;
    currency: string;
    spent: number;
    percentage: number;
    remaining: number;
    conversion_error: boolean;
  }> {
    const userRows = await sql`SELECT currency, total_budget FROM users WHERE id = ${userId}`;
    const currency = (userRows[0] as any)?.currency || 'LKR';
    const rawTotal = (userRows[0] as any)?.total_budget;
    const amount = rawTotal !== null && rawTotal !== undefined ? Number(rawTotal) : null;

    const { startDate, endDate } = this.periodWindow('monthly');
    const rows = await sql`
      SELECT amount, currency FROM transactions
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND transfer_id IS NULL
        AND amount < 0
        AND created_at >= ${startDate}::date
        AND created_at <= ${endDate}::date
    `;

    let spent = 0;
    let conversionError = false;
    for (const r of rows as any[]) {
      const abs = Math.abs(Number(r.amount));
      const cur = String(r.currency || 'LKR');
      if (cur === currency) {
        spent += abs;
      } else {
        try {
          spent += await convert(abs, cur, currency);
        } catch {
          conversionError = true;
        }
      }
    }

    spent = Math.round(spent * 100) / 100;
    const percentage = amount && amount > 0 ? Math.round((spent / amount) * 100) : 0;
    const remaining = amount ? Math.max(0, Math.round((amount - spent) * 100) / 100) : 0;
    return { amount, currency, spent, percentage, remaining, conversion_error: conversionError };
  }

  static async findByCategory(userId: string, category: string): Promise<BudgetRow | null> {
    const rows = await sql`
      SELECT id, user_id, category, amount, currency, period, created_at
      FROM budgets
      WHERE user_id = ${userId} AND category = ${category} AND deleted_at IS NULL
    `;
    return (rows[0] as BudgetRow) || null;
  }

  /**
   * Spend for one category over a window (defaults to the current month, open
   * upper bound). Pass startDate/endDate to measure a budget's own period.
   */
  static async getCategorySpent(
    userId: string,
    category: string,
    currency: string = 'LKR',
    startDate?: string,
    endDate?: string,
  ): Promise<number> {
    const now = new Date();
    const start = startDate ?? `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
    const end = endDate ?? '9999-12-31'; // effectively no upper bound by default

    const rows = await sql`
      WITH unsplit_expenses AS (
        SELECT ABS(SUM(t.amount)) AS total, t.currency AS currency
        FROM transactions t
        WHERE t.user_id = ${userId}
          AND t.category = ${category}
          AND t.amount < 0
          AND t.deleted_at IS NULL
          AND t.created_at >= ${start}::date
          AND t.created_at <= ${end}::date
          AND NOT EXISTS (
            SELECT 1
            FROM transaction_splits s
            WHERE s.transaction_id = t.id
          )
        GROUP BY t.currency
      ),
      split_expenses AS (
        SELECT ABS(SUM(s.amount)) AS total, t.currency AS currency
        FROM transaction_splits s
        INNER JOIN transactions t ON t.id = s.transaction_id
        WHERE s.user_id = ${userId}
          AND t.user_id = ${userId}
          AND s.category = ${category}
          AND s.amount < 0
          AND t.created_at >= ${start}::date
          AND t.created_at <= ${end}::date
        GROUP BY t.currency
      ),
      combined AS (
        SELECT total, currency FROM unsplit_expenses
        UNION ALL
        SELECT total, currency FROM split_expenses
      )
      SELECT SUM(total) AS total, currency
      FROM combined
      GROUP BY currency
    `;

    let spent = 0;
    for (const row of rows as any[]) {
      const absAmount = Number(row.total);
      const txCurrency = String(row.currency || 'LKR');
      try {
        spent += await convert(absAmount, txCurrency, currency);
      } catch {
        spent += absAmount;
      }
    }
    return Math.round(spent * 100) / 100;
  }

  // ── Alert dedupe + pacing state ───────────────────────────────────────────

  static async getAlertState(
    id: number,
  ): Promise<{ period: string | null; level: number; paceAlerted: boolean }> {
    const rows = await sql`SELECT alert_period, alert_level, pace_alerted FROM budgets WHERE id = ${id}`;
    const r = rows[0] as any;
    return {
      period: r?.alert_period ?? null,
      level: Number(r?.alert_level ?? 0),
      paceAlerted: r?.pace_alerted === true,
    };
  }

  /**
   * Records that a threshold alert (80/100) was sent for [period]. When the
   * period key changes, pace_alerted resets so a new window starts clean.
   */
  static async setAlertLevel(id: number, period: string, level: number): Promise<void> {
    await sql`
      UPDATE budgets
      SET alert_level = ${level},
          pace_alerted = CASE WHEN alert_period = ${period} THEN pace_alerted ELSE false END,
          alert_period = ${period}
      WHERE id = ${id}
    `;
  }

  /** Records the one pacing alert for [period], resetting threshold level on a new window. */
  static async markPaceAlerted(id: number, period: string): Promise<void> {
    await sql`
      UPDATE budgets
      SET pace_alerted = true,
          alert_level = CASE WHEN alert_period = ${period} THEN alert_level ELSE 0 END,
          alert_period = ${period}
      WHERE id = ${id}
    `;
  }

  /** All budgets across users (for the pacing sweep). */
  static async listAllActive(): Promise<Array<BudgetRow & { pace_alerted: boolean; alert_period: string | null }>> {
    const rows = await sql`
      SELECT id, user_id, category, amount, currency, period, created_at, pace_alerted, alert_period
      FROM budgets
      WHERE deleted_at IS NULL
    `;
    return rows as any[];
  }
}
