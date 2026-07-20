import { sql } from '../config/db';

export type DebtDirection = 'owed_to_me' | 'i_owe';
export type DebtStatus = 'open' | 'settled';

export interface Debt {
  id: number;
  user_id: string;
  counterparty_name: string;
  amount: number;
  currency: string;
  direction: DebtDirection;
  note?: string | null;
  status: DebtStatus;
  created_at: Date;
  settled_at?: Date | null;
}

export class DebtModel {
  static async listByUser(userId: string, limit = 200, offset = 0): Promise<Debt[]> {
    const rows = await sql`
      SELECT id, user_id, counterparty_name, amount, currency, direction, note, status, created_at, settled_at
      FROM debts
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY status ASC, created_at DESC, id DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as Debt[];
  }

  static async findById(userId: string, id: number): Promise<Debt | null> {
    const rows = await sql`
      SELECT id, user_id, counterparty_name, amount, currency, direction, note, status, created_at, settled_at
      FROM debts
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as Debt) || null;
  }

  /**
   * [isNew] tells the caller whether a row was actually inserted: the optional
   * wallet movement at create time must only be written for a fresh insert,
   * never for an idempotent offline replay.
   */
  static async create(
    userId: string,
    counterpartyName: string,
    amount: number,
    currency: string,
    direction: DebtDirection,
    note?: string | null,
    clientOpId?: string | null,
  ): Promise<{ debt: Debt; isNew: boolean }> {
    const opId = clientOpId && clientOpId.trim() ? clientOpId.trim() : null;

    // Idempotent create: an offline replay with the same op id returns the
    // existing row instead of inserting a duplicate (same as transactions).
    if (opId) {
      const existing = await sql`
        SELECT id, user_id, counterparty_name, amount, currency, direction, note, status, created_at, settled_at
        FROM debts
        WHERE user_id = ${userId} AND client_op_id = ${opId} AND deleted_at IS NULL
      `;
      if (existing[0]) return { debt: existing[0] as Debt, isNew: false };
    }

    const rows = await sql`
      INSERT INTO debts (user_id, counterparty_name, amount, currency, direction, note, client_op_id)
      VALUES (${userId}, ${counterpartyName}, ${amount}, ${currency}, ${direction}, ${note ?? null}, ${opId})
      RETURNING id, user_id, counterparty_name, amount, currency, direction, note, status, created_at, settled_at
    `;
    return { debt: rows[0] as Debt, isNew: true };
  }

  /**
   * Settles an OPEN debt; returns null when there was nothing open to settle
   * (missing, deleted, or already settled). Matching on status makes the
   * transition one-shot, which the controller relies on: the wallet movement
   * rides on a successful transition, so a double-tap or offline replay can't
   * move the money twice.
   */
  static async settle(userId: string, id: number): Promise<Debt | null> {
    const rows = await sql`
      UPDATE debts
      SET status = 'settled', settled_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL AND status = 'open'
      RETURNING id, user_id, counterparty_name, amount, currency, direction, note, status, created_at, settled_at
    `;
    return (rows[0] as Debt) || null;
  }

  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE debts SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    return rows.length > 0;
  }
}
