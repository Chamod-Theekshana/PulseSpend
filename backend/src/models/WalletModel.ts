import { sql } from '../config/db';
import { convert } from '../services/exchangeRateService';

export interface Wallet {
  id: number;
  user_id: string;
  name: string;
  type: 'cash' | 'bank' | 'card' | string;
  currency: string;
  created_at: Date;
}

export interface WalletBalance extends Wallet {
  income: number;
  expense: number;
  balance: number;
  /** Balances are converted into this (the user's preferred) currency. */
  display_currency: string;
}

const WALLET_TYPES = ['cash', 'bank', 'card'];

export class WalletModel {
  static normalizeType(type: unknown): string {
    const t = String(type ?? '').toLowerCase().trim();
    return WALLET_TYPES.includes(t) ? t : 'cash';
  }

  static async listByUser(userId: string): Promise<Wallet[]> {
    const rows = await sql`
      SELECT id, user_id, name, type, currency, created_at
      FROM wallets
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY created_at ASC, id ASC
    `;
    return rows as Wallet[];
  }

  static async findById(userId: string, id: number): Promise<Wallet | null> {
    const rows = await sql`
      SELECT id, user_id, name, type, currency, created_at
      FROM wallets
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as Wallet) || null;
  }

  static async create(userId: string, name: string, type: string, currency: string): Promise<Wallet> {
    const rows = await sql`
      INSERT INTO wallets (user_id, name, type, currency)
      VALUES (${userId}, ${name}, ${this.normalizeType(type)}, ${currency})
      RETURNING id, user_id, name, type, currency, created_at
    `;
    return rows[0] as Wallet;
  }

  static async update(
    userId: string,
    id: number,
    fields: { name?: string; type?: string; currency?: string },
  ): Promise<Wallet | null> {
    const rows = await sql`
      UPDATE wallets
      SET
        name = COALESCE(${fields.name ?? null}, name),
        type = COALESCE(${fields.type !== undefined ? this.normalizeType(fields.type) : null}, type),
        currency = COALESCE(${fields.currency ?? null}, currency)
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, name, type, currency, created_at
    `;
    return (rows[0] as Wallet) || null;
  }

  /** Soft-deletes the wallet; its transactions survive (wallet_id → NULL = default). */
  static async delete(userId: string, id: number): Promise<boolean> {
    const rows = await sql`
      UPDATE wallets SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id
    `;
    if (rows.length === 0) return false;
    await sql`UPDATE transactions SET wallet_id = NULL WHERE user_id = ${userId} AND wallet_id = ${id}`;
    return true;
  }

  /**
   * Per-wallet income/expense/balance in the user's preferred currency, plus a
   * synthetic "Cash (default)" bucket for transactions with wallet_id = NULL.
   */
  static async balances(userId: string, preferredCurrency: string): Promise<WalletBalance[]> {
    const wallets = await this.listByUser(userId);
    const rows = await sql`
      SELECT wallet_id, amount, currency
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;

    const totals = new Map<number | null, { income: number; expense: number }>();
    for (const r of rows) {
      const walletId = (r as any).wallet_id === null ? null : Number((r as any).wallet_id);
      const amt = Number((r as any).amount);
      const cur = ((r as any).currency as string) || 'LKR';
      let converted = amt;
      try {
        converted = await convert(amt, cur, preferredCurrency);
      } catch {
        converted = amt;
      }
      const entry = totals.get(walletId) ?? { income: 0, expense: 0 };
      if (converted >= 0) entry.income += converted;
      else entry.expense += Math.abs(converted);
      totals.set(walletId, entry);
    }

    const result: WalletBalance[] = wallets.map((w) => {
      const t = totals.get(Number(w.id)) ?? { income: 0, expense: 0 };
      return {
        ...w,
        income: t.income,
        expense: t.expense,
        balance: t.income - t.expense,
        display_currency: preferredCurrency,
      };
    });

    // Unassigned/legacy transactions live in a virtual default bucket (id 0).
    const unassigned = totals.get(null);
    if (unassigned && (unassigned.income !== 0 || unassigned.expense !== 0)) {
      result.unshift({
        id: 0,
        user_id: userId,
        name: 'Default',
        type: 'cash',
        currency: preferredCurrency,
        created_at: new Date(0),
        income: unassigned.income,
        expense: unassigned.expense,
        balance: unassigned.income - unassigned.expense,
        display_currency: preferredCurrency,
      });
    }
    return result;
  }
}
