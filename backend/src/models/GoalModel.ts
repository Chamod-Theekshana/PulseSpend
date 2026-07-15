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
  auto_amount?: number | null;
  auto_day?: number | null;
  group_id?: number | null;
  /** Calculated field: percentage towards target */
  progress_percentage?: number;
}

export class GoalModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<Goal[]> {
    const rows = await sql`
      SELECT
        id, user_id, name, target_amount, current_amount, currency,
        deadline, is_completed, created_at, auto_amount, auto_day,
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
        deadline, is_completed, created_at, last_milestone, auto_amount, auto_day,
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
    groupId?: number | null,
  ): Promise<Goal> {
    const group = groupId && groupId > 0 ? groupId : null;
    const rows = deadline
      ? await sql`
          INSERT INTO goals (user_id, name, target_amount, currency, deadline, group_id)
          VALUES (${userId}, ${name}, ${targetAmount}, ${currency}, ${deadline}, ${group})
          RETURNING *, 0 AS progress_percentage
        `
      : await sql`
          INSERT INTO goals (user_id, name, target_amount, currency, group_id)
          VALUES (${userId}, ${name}, ${targetAmount}, ${currency}, ${group})
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

  /**
   * Applies a deposit (positive) or withdrawal (negative) and records it in
   * goal_contributions. current_amount is clamped to [0, target]; a withdrawal
   * below target un-completes the goal. [source] tags the origin
   * ('manual' | 'auto' | 'roundup') for the timeline UI.
   */
  static async addContribution(
    userId: string,
    id: number,
    amount: number,
    source: string = 'manual',
  ): Promise<Goal | null> {
    const rows = await sql`
      UPDATE goals
      SET
        current_amount = GREATEST(0, LEAST(current_amount + ${amount}, target_amount)),
        is_completed = (GREATEST(0, LEAST(current_amount + ${amount}, target_amount)) >= target_amount)
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING *,
        CASE WHEN target_amount > 0
          THEN ROUND((current_amount / target_amount) * 100, 1)
          ELSE 0
        END AS progress_percentage
    `;
    const goal = (rows[0] as Goal) || null;
    if (goal) {
      await sql`
        INSERT INTO goal_contributions (goal_id, user_id, amount, source)
        VALUES (${id}, ${userId}, ${amount}, ${source})
      `;
    }
    return goal;
  }

  /**
   * A goal the user may act on: their own, or any goal shared with a group
   * they belong to. Used by contribute/timeline for group goals.
   */
  static async findAccessible(userId: string, id: number): Promise<Goal | null> {
    const rows = await sql`
      SELECT
        g.id, g.user_id, g.name, g.target_amount, g.current_amount, g.currency,
        g.deadline, g.is_completed, g.created_at, g.last_milestone, g.auto_amount,
        g.auto_day, g.group_id,
        CASE WHEN g.target_amount > 0
          THEN ROUND((g.current_amount / g.target_amount) * 100, 1)
          ELSE 0
        END AS progress_percentage
      FROM goals g
      WHERE g.id = ${id} AND g.deleted_at IS NULL
        AND (
          g.user_id = ${userId}
          OR (g.group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM group_members gm
            WHERE gm.group_id = g.group_id AND gm.user_id = ${userId}
          ))
        )
    `;
    return (rows[0] as Goal) || null;
  }

  /**
   * Contribution by any member with access (the caller must have verified via
   * findAccessible). The contribution row records WHO contributed.
   */
  static async addContributionById(
    goalId: number,
    contributorId: string,
    amount: number,
    source: string = 'manual',
  ): Promise<Goal | null> {
    const rows = await sql`
      UPDATE goals
      SET
        current_amount = GREATEST(0, LEAST(current_amount + ${amount}, target_amount)),
        is_completed = (GREATEST(0, LEAST(current_amount + ${amount}, target_amount)) >= target_amount)
      WHERE id = ${goalId} AND deleted_at IS NULL
      RETURNING *,
        CASE WHEN target_amount > 0
          THEN ROUND((current_amount / target_amount) * 100, 1)
          ELSE 0
        END AS progress_percentage
    `;
    const goal = (rows[0] as Goal) || null;
    if (goal) {
      await sql`
        INSERT INTO goal_contributions (goal_id, user_id, amount, source)
        VALUES (${goalId}, ${contributorId}, ${amount}, ${source})
      `;
    }
    return goal;
  }

  /** Goals shared with a group, for the group detail screen. */
  static async listByGroup(groupId: number): Promise<Goal[]> {
    const rows = await sql`
      SELECT
        id, user_id, name, target_amount, current_amount, currency,
        deadline, is_completed, created_at, group_id,
        CASE WHEN target_amount > 0
          THEN ROUND((current_amount / target_amount) * 100, 1)
          ELSE 0
        END AS progress_percentage
      FROM goals
      WHERE group_id = ${groupId} AND deleted_at IS NULL
      ORDER BY is_completed ASC, created_at DESC
    `;
    return rows as Goal[];
  }

  /** Sets or clears (nulls) the monthly auto-contribution rule. */
  static async setAutoRule(
    userId: string,
    id: number,
    autoAmount: number | null,
    autoDay: number | null,
  ): Promise<Goal | null> {
    const rows = await sql`
      UPDATE goals
      SET auto_amount = ${autoAmount}, auto_day = ${autoDay}
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING *,
        CASE WHEN target_amount > 0
          THEN ROUND((current_amount / target_amount) * 100, 1)
          ELSE 0
        END AS progress_percentage
    `;
    return (rows[0] as Goal) || null;
  }

  /** Active auto-rules due on [day] that haven't auto-contributed today yet. */
  static async listDueAutoRules(day: number) {
    return sql`
      SELECT g.id, g.user_id, g.name, g.auto_amount, g.currency
      FROM goals g
      WHERE g.deleted_at IS NULL
        AND g.is_completed = false
        AND g.auto_amount IS NOT NULL AND g.auto_amount > 0
        AND g.auto_day = ${day}
        AND NOT EXISTS (
          SELECT 1 FROM goal_contributions c
          WHERE c.goal_id = g.id AND c.source = 'auto'
            AND c.created_at::date = CURRENT_DATE
        )
    `;
  }

  /**
   * Contribution timeline, newest first — includes every member's rows (the
   * caller verifies access first via findAccessible) with a display name for
   * group-goal member breakdowns.
   */
  static async listContributions(goalId: number, limit = 100) {
    const rows = await sql`
      SELECT c.id, c.goal_id, c.user_id, c.amount, c.source, c.created_at,
             COALESCE(u.name, split_part(u.email, '@', 1)) AS contributor_name
      FROM goal_contributions c
      LEFT JOIN users u ON u.id::text = c.user_id
      WHERE c.goal_id = ${goalId}
      ORDER BY c.created_at DESC, c.id DESC
      LIMIT ${limit}
    `;
    return rows;
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
