import { sql } from '../config/db';

export type ReminderRow = {
  id: number;
  user_id: string;
  title: string;
  amount: number;
  currency: string;
  category: string;
  due_date: string;
  remind_days_before: number;
  is_active: boolean;
  last_notified_on?: string | null;
  created_at: string;
};

export class ReminderModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<ReminderRow[]> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
      FROM reminders
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY due_date ASC, id DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as ReminderRow[];
  }

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM reminders
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async findById(userId: string, id: number): Promise<ReminderRow | null> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
      FROM reminders
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as ReminderRow) || null;
  }

  static async create(
    userId: string,
    title: string,
    amount: number,
    category: string,
    dueDate: string,
    remindDaysBefore: number,
    currency = 'LKR',
    isActive = true,
  ): Promise<ReminderRow> {
    const rows = await sql`
      INSERT INTO reminders (user_id, title, amount, currency, category, due_date, remind_days_before, is_active)
      VALUES (${userId}, ${title}, ${amount}, ${currency}, ${category}, ${dueDate}::date, ${remindDaysBefore}, ${isActive})
      RETURNING id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
    `;
    return rows[0] as ReminderRow;
  }

  static async update(
    userId: string,
    id: number,
    fields: {
      title?: string;
      amount?: number;
      currency?: string;
      category?: string;
      due_date?: string;
      remind_days_before?: number;
      is_active?: boolean;
    },
  ): Promise<ReminderRow | null> {
    const shouldResetNotified =
      fields.due_date !== undefined ||
      fields.remind_days_before !== undefined ||
      fields.is_active !== undefined;

    const rows = await sql`
      UPDATE reminders
      SET
        title = COALESCE(${fields.title ?? null}, title),
        amount = COALESCE(${fields.amount ?? null}, amount),
        currency = COALESCE(${fields.currency ?? null}, currency),
        category = COALESCE(${fields.category ?? null}, category),
        due_date = COALESCE(${fields.due_date ?? null}::date, due_date),
        remind_days_before = COALESCE(${fields.remind_days_before ?? null}, remind_days_before),
        is_active = COALESCE(${fields.is_active ?? null}, is_active),
        last_notified_on = CASE
          WHEN ${shouldResetNotified}::boolean THEN NULL
          ELSE last_notified_on
        END
      WHERE id = ${id} AND user_id = ${userId}
        AND deleted_at IS NULL
      RETURNING id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
    `;

    return (rows[0] as ReminderRow) || null;
  }

  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE reminders
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    return rows.length > 0;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    if (ids.length === 0) return 0;
    const rows = await sql`
      UPDATE reminders
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }

  static async listDueForReminderDate(today: string): Promise<ReminderRow[]> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
      FROM reminders
      WHERE is_active = true
        AND deleted_at IS NULL
        AND due_date >= ${today}::date
        AND (due_date::date - ${today}::date) = remind_days_before
        AND (last_notified_on IS NULL OR last_notified_on::date <> ${today}::date)
      ORDER BY due_date ASC, id ASC
    `;

    return rows as ReminderRow[];
  }

  /**
   * Active bills whose due date has passed and that haven't yet had an *overdue*
   * notification. The `last_notified_on <= due_date` guard means only pre-due
   * reminders (or none) have fired so far; once we notify overdue we stamp
   * `last_notified_on = today` (> due_date) so it fires exactly once.
   */
  static async listOverdue(today: string): Promise<ReminderRow[]> {
    const rows = await sql`
      SELECT id, user_id, title, amount, currency, category, due_date, remind_days_before, is_active, last_notified_on, created_at
      FROM reminders
      WHERE is_active = true
        AND deleted_at IS NULL
        AND due_date < ${today}::date
        AND (last_notified_on IS NULL OR last_notified_on::date <= due_date::date)
      ORDER BY due_date ASC, id ASC
    `;
    return rows as ReminderRow[];
  }

  static async markNotified(id: number, notificationDate: string): Promise<void> {
    await sql`
      UPDATE reminders
      SET last_notified_on = ${notificationDate}::date
      WHERE id = ${id}
    `;
  }
}
