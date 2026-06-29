import { sql } from '../config/db';

export interface Goal {
  id: number;
  user_id: string;
  name: string;
  target_amount: number;
  current_amount: number;
  currency: string;
  deadline?: string | null;
  is_completed: boolean;
  created_at: string;
  /** Calculated field: percentage towards target */
  progress_percentage?: number;
}

export class GoalModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<Goal[]> {
    const rows = await sql`
      SELECT 
        id, user_id, name, target_amount, current_amount, currency,
        deadline, is_completed, created_at,
        CASE WHEN target_amount > 0 
          THEN ROUND((current_amount / target_amount) * 100, 1) 
          ELSE 0 
        END AS progress_percentage
      FROM goals
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY is_completed ASC, created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as Goal[];
  }

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM goals
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async findById(userId: string, id: number): Promise<Goal | null> {
    const rows = await sql`
      SELECT 
        id, user_id, name, target_amount, current_amount, currency,
        deadline, is_completed, created_at,
        CASE WHEN target_amount > 0 
          THEN ROUND((current_amount / target_amount) * 100, 1) 
          ELSE 0 
        END AS progress_percentage
      FROM goals
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as Goal) || null;
  }

  static async create(
    userId: string,
    name: string,
    targetAmount: number,
    currency: string = 'LKR',
    deadline?: string | null,
  ): Promise<Goal> {
    const rows = deadline
      ? await sql`
          INSERT INTO goals (user_id, name, target_amount, currency, deadline)
          VALUES (${userId}, ${name}, ${targetAmount}, ${currency}, ${deadline})
          RETURNING *, 0 AS progress_percentage
        `
      : await sql`
          INSERT INTO goals (user_id, name, target_amount, currency)
          VALUES (${userId}, ${name}, ${targetAmount}, ${currency})
          RETURNING *, 0 AS progress_percentage
        `;
    return rows[0] as Goal;
  }

  static async update(
    userId: string,
    id: number,
    name: string,
    targetAmount: number,
    currency: string,
    deadline?: string | null,
  ): Promise<Goal | null> {
    const rows = deadline
      ? await sql`
          UPDATE goals
          SET name = ${name}, target_amount = ${targetAmount}, currency = ${currency}, deadline = ${deadline}
          WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
          RETURNING *
        `
      : await sql`
          UPDATE goals
          SET name = ${name}, target_amount = ${targetAmount}, currency = ${currency}, deadline = NULL
          WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
          RETURNING *
        `;
    return (rows[0] as Goal) || null;
  }

  static async addContribution(
    userId: string,
    id: number,
    amount: number,
  ): Promise<Goal | null> {
    const rows = await sql`
      UPDATE goals
      SET 
        current_amount = LEAST(current_amount + ${amount}, target_amount),
        is_completed = CASE 
          WHEN (current_amount + ${amount}) >= target_amount THEN true 
          ELSE is_completed 
        END
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING *,
        CASE WHEN target_amount > 0 
          THEN ROUND((current_amount / target_amount) * 100, 1) 
          ELSE 0 
        END AS progress_percentage
    `;
    return (rows[0] as Goal) || null;
  }

  static async delete(userId: string, id: number): Promise<void> {
    await sql`
      UPDATE goals
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    if (ids.length === 0) return 0;
    const rows = await sql`
      UPDATE goals
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }
}
