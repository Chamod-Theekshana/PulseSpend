import crypto from 'crypto';
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

// cash/bank/investment count as assets; credit/loan as liabilities ('card' is
// treated as a liability alias of credit for net-worth purposes).
const WALLET_TYPES = ['cash', 'bank', 'card', 'credit', 'investment', 'loan'];
const LIABILITY_TYPES = new Set(['credit', 'loan', 'card']);

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

  /**
   * Moves money between two wallets as a pair of transactions (−from / +to)
   * sharing one transfer uuid. Wallet id 0 = the virtual default bucket
   * (wallet_id NULL). Both legs use [currency] (the user's display currency)
   * so they cancel exactly in converted totals. Neon's HTTP driver has no
   * cross-statement transactions, so the − leg is inserted first: an orphaned
   * − leg understates a balance rather than inventing money.
   */
  static async transfer(
    userId: string,
    fromWalletId: number,
    toWalletId: number,
    amount: number,
    currency: string,
    fromName: string,
    toName: string,
  ): Promise<{ transferId: string }> {
    const transferId = crypto.randomUUID();
    const fromId = fromWalletId === 0 ? null : fromWalletId;
    const toId = toWalletId === 0 ? null : toWalletId;

    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${'Transfer to ' + toName}, ${-Math.abs(amount)}, 'Transfer', ${currency}, ${fromId}, ${transferId}, NOW())
    `;
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${'Transfer from ' + fromName}, ${Math.abs(amount)}, 'Transfer', ${currency}, ${toId}, ${transferId}, NOW())
    `;
    return { transferId };
  }

  /**
   * Net worth = assets − liabilities, in the user's display currency.
   * Asset wallets (cash/bank/investment + the default bucket) contribute their
   * balance; liability wallets (credit/card/loan) contribute how much is OWED —
   * the absolute value of a negative balance (spending on credit drives the
   * wallet's balance down).
   */
  static async netWorth(userId: string, preferredCurrency: string) {
    const balances = await this.balances(userId, preferredCurrency);

    let assets = 0;
    let liabilities = 0;
    const byType = new Map<string, { type: string; total: number; isLiability: boolean }>();

    for (const b of balances) {
      const isLiability = LIABILITY_TYPES.has(b.type);
      const value = isLiability ? Math.max(0, -b.balance) : b.balance;
      if (isLiability) liabilities += value;
      else assets += value;

      const entry = byType.get(b.type) ?? { type: b.type, total: 0, isLiability };
      entry.total += value;
      byType.set(b.type, entry);
    }

    const round = (n: number) => Math.round(n * 100) / 100;
    return {
      assets: round(assets),
      liabilities: round(liabilities),
      netWorth: round(assets - liabilities),
      currency: preferredCurrency,
      byType: [...byType.values()].map((t) => ({ ...t, total: round(t.total) })),
    };
  }
}
