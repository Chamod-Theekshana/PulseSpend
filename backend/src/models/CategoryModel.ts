import { sql } from '../config/db';

export type CategoryRow = {
  id: number;
  user_id: string;
  name: string;
  type: 'expense' | 'income' | 'both';
  created_at: string;
};

export class CategoryModel {
  static async listByUser(userId: string, limit: number, offset: number): Promise<CategoryRow[]> {
    const rows = await sql`
      SELECT id, user_id, name, type, created_at
      FROM categories
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY name ASC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as CategoryRow[];
  }

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM categories
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async create(
    userId: string,
    name: string,
    type: 'expense' | 'income' | 'both' = 'expense'
  ): Promise<CategoryRow> {
    const rows = await sql`
      INSERT INTO categories (user_id, name, type)
      VALUES (${userId}, ${name}, ${type})
      RETURNING id, user_id, name, type, created_at
    `;
    return rows[0] as CategoryRow;
  }

  static async update(
    userId: string,
    id: number,
    name: string,
    type: 'expense' | 'income' | 'both'
  ): Promise<CategoryRow | null> {
    const rows = await sql`
      UPDATE categories
      SET name = ${name}, type = ${type}
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, name, type, created_at
    `;
    return (rows[0] as CategoryRow) || null;
  }

  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE categories
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    return rows.length > 0;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    if (ids.length === 0) return 0;
    const rows = await sql`
      UPDATE categories
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }

  static async seedDefaults(userId: string): Promise<void> {
    const existing = await sql`
      SELECT COUNT(*)::int AS c FROM categories WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    if (Number((existing[0] as any)?.c ?? 0) > 0) return;

    const defaults: Array<{ name: string; type: 'expense' | 'income' | 'both' }> = [
      { name: 'Food', type: 'expense' },
      { name: 'Transport', type: 'expense' },
      { name: 'Bills', type: 'expense' },
      { name: 'Shopping', type: 'expense' },
      { name: 'Health', type: 'expense' },
      { name: 'Entertainment', type: 'expense' },
      { name: 'Other', type: 'expense' },
      { name: 'Salary', type: 'income' },
      { name: 'Income', type: 'income' },
    ];

    for (const d of defaults) {
      await sql`
        INSERT INTO categories (user_id, name, type)
        VALUES (${userId}, ${d.name}, ${d.type})
        ON CONFLICT (user_id, name) DO NOTHING
      `;
    }
  }
}
