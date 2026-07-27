import crypto from 'crypto';
import { sql } from '../config/db';
import { convert, prefetchRates, convertSync } from '../services/exchangeRateService';
import { netWorthContribution, liabilityBreakdown, moneyOnHand as foldMoneyOnHand } from '../utils/financeMath';

export interface Wallet {
  id: number;
  user_id: string;
  name: string;
  type: 'cash' | 'bank' | 'card' | string;
  currency: string;
  /** Amount the wallet was seeded with on create; for liabilities, the original
   *  amount owed (positive). NULL = wallet started empty. */
  opening_balance: number | null;
  /** Transfer uuid tying the wallet to its opening seed leg(s), so the seed can
   *  be found and replaced when the opening balance is corrected. */
  opening_transfer_id: string | null;
  /** Spending ceiling for credit/card wallets, in the wallet's own currency: a
   *  charge that would push the amount owed past it is refused. NULL = none. */
  credit_limit: number | null;
  created_at: Date;
}

export interface WalletBalance extends Wallet {
  income: number;
  expense: number;
  balance: number;
  /**
   * UNLIKE `Wallet.opening_balance`, this is converted into `display_currency`
   * like every other figure here. The raw column is in the *wallet's* currency,
   * so comparing it against these totals (payoff progress, the charged/borrowed
   * split) is only valid once it's on the same basis.
   */
  opening_balance: number | null;
  /** Like `opening_balance`, converted into `display_currency` so "available
   *  credit" can be computed against the converted owed amount. */
  credit_limit: number | null;
  /** What was owed at the start — the opening seed, in `display_currency`. */
  borrowed: number;
  /** Real charges since, i.e. `expense` minus the seed. */
  charged: number;
  /** Repayments — the `+` legs of transfers into this wallet. */
  repaid: number;
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

  /** Credit/card/loan wallets hold debt: a negative balance is what's owed. */
  static isLiabilityType(type: unknown): boolean {
    return LIABILITY_TYPES.has(this.normalizeType(type));
  }

  /**
   * Whether [type] is one we actually support. Writes must check this rather
   * than lean on `normalizeType`, which coerces anything unrecognised to
   * 'cash' — so a typo'd 'lone' would silently turn a debt into an asset.
   */
  static isKnownType(type: unknown): boolean {
    return WALLET_TYPES.includes(String(type ?? '').toLowerCase().trim());
  }

  /** Any live transaction against this wallet, including its opening seed. */
  static async hasTransactions(userId: string, walletId: number): Promise<boolean> {
    const rows = await sql`
      SELECT 1 FROM transactions
      WHERE user_id = ${userId} AND wallet_id = ${walletId} AND deleted_at IS NULL
      LIMIT 1
    `;
    return rows.length > 0;
  }

  static async listByUser(userId: string): Promise<Wallet[]> {
    const rows = await sql`
      SELECT id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      FROM wallets
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY created_at ASC, id ASC
    `;
    return rows as Wallet[];
  }

  static async findById(userId: string, id: number): Promise<Wallet | null> {
    const rows = await sql`
      SELECT id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      FROM wallets
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    return (rows[0] as Wallet) || null;
  }

  static async create(
    userId: string,
    name: string,
    type: string,
    currency: string,
    openingBalance: number | null = null,
  ): Promise<Wallet> {
    const rows = await sql`
      INSERT INTO wallets (user_id, name, type, currency, opening_balance)
      VALUES (${userId}, ${name}, ${this.normalizeType(type)}, ${currency}, ${openingBalance})
      RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
    `;
    return rows[0] as Wallet;
  }

  /**
   * Creates a wallet and seeds what's already in it, atomically.
   *
   * The wallet row and its seed have to land together: a wallet carrying an
   * `opening_balance` with no seed transaction reports a debt of nothing, which
   * `payoffProgress` renders as "100% paid off". A data-modifying CTE keeps it
   * to one statement, which the HTTP driver runs atomically.
   *
   * Two shapes, by where the money went:
   * - **[drawdown] given** — new borrowing. Two legs sharing one transfer id:
   *   the debt on this wallet, the cash on the destination. Net-worth-neutral,
   *   because the cash is as real as the debt. The user then spends from the
   *   destination and this wallet just tracks what's owed.
   * - **no [drawdown]** — money already spent, or an asset's starting balance.
   *   One leg. For a liability that correctly drops net worth: the debt exists
   *   and whatever it bought is gone.
   *
   * Either way the seed carries a transfer id, so it never counts as earning or
   * spending — an opening balance is neither.
   */
  static async createWithOpening(
    userId: string,
    name: string,
    type: string,
    currency: string,
    opening: number,
    drawdown?: { walletId: number; walletName: string },
    creditLimit: number | null = null,
  ): Promise<Wallet> {
    const normalized = this.normalizeType(type);
    const isLiability = LIABILITY_TYPES.has(normalized);
    const transferId = crypto.randomUUID();
    const abs = Math.abs(opening);

    // "It's empty" is a real answer and worth recording — 0 means the user said
    // so, NULL means nobody ever asked (a wallet predating the field), and the
    // correction sheet warns differently for each. But there's nothing to seed,
    // so no transaction: a 0-amount row is noise in the ledger. Mirrors
    // replaceOpening(…, 0), which likewise clears the seed and the uuid.
    if (abs === 0) {
      const rows = await sql`
        INSERT INTO wallets (user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit)
        VALUES (${userId}, ${name}, ${normalized}, ${currency}, 0, NULL, ${creditLimit})
        RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      `;
      return rows[0] as Wallet;
    }

    // The ::numeric and ::integer casts below are load-bearing — don't drop them.
    // `INSERT ... VALUES` infers each parameter's type from the target column,
    // but `INSERT ... SELECT` resolves the SELECT's output types FIRST, and the
    // driver sends parameters untyped — so they arrive as `text` and the insert
    // fails ("column amount is of type numeric but expression is of type text").
    // Only non-text targets need it: text → varchar is a valid assignment cast,
    // which is why user_id/title/category/currency/transfer_id are fine bare.
    if (drawdown) {
      // Wallet id 0 = the virtual default bucket (wallet_id NULL).
      const destId = drawdown.walletId === 0 ? null : drawdown.walletId;
      const rows = await sql`
        WITH w AS (
          INSERT INTO wallets (user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit)
          VALUES (${userId}, ${name}, ${normalized}, ${currency}, ${abs}, ${transferId}, ${creditLimit})
          RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
        ), legs AS (
          INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
          SELECT ${userId}, ${'Borrowed — ' + name}, ${-abs}::numeric, 'Transfer', ${currency}, w.id, ${transferId}, NOW() FROM w
          UNION ALL
          SELECT ${userId}, ${'Loan from ' + name}, ${abs}::numeric, 'Transfer', ${currency}, ${destId}::integer, ${transferId}, NOW() FROM w
        )
        SELECT * FROM w
      `;
      return rows[0] as Wallet;
    }

    const signed = isLiability ? -abs : abs;
    const title = isLiability ? 'Opening balance (amount owed)' : 'Opening balance';
    const rows = await sql`
      WITH w AS (
        INSERT INTO wallets (user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit)
        VALUES (${userId}, ${name}, ${normalized}, ${currency}, ${abs}, ${transferId}, ${creditLimit})
        RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      ), seed AS (
        INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
        SELECT ${userId}, ${title}, ${signed}::numeric, 'Opening Balance', ${currency}, w.id, ${transferId}, NOW() FROM w
      )
      SELECT * FROM w
    `;
    return rows[0] as Wallet;
  }

  /**
   * Replaces a wallet's opening balance — the create-time answer to "how much
   * is in it / how much do you owe", corrected.
   *
   * Replacement rather than an adjusting entry: someone fixing a number they
   * mistyped expects it changed, not a second row explaining the difference.
   * The old seed is soft-deleted (`balances()` already filters `deleted_at`) so
   * the correction stays auditable, and a fresh uuid is minted so the wallet
   * always points at exactly its live seed.
   *
   * One statement: the delete, the new leg(s) and the wallet's own columns have
   * to move together or the wallet's `opening_balance` stops matching the
   * transactions behind it.
   *
   * A wallet seeded before `opening_transfer_id` existed, or never seeded at
   * all, has nothing to delete — `transfer_id = NULL` matches no row — so this
   * simply adds the seed it never had. Its balance will move by the full amount.
   */
  static async replaceOpening(
    userId: string,
    wallet: Wallet,
    opening: number,
    drawdown?: { walletId: number; walletName: string },
  ): Promise<Wallet | null> {
    const isLiability = LIABILITY_TYPES.has(wallet.type);
    const old = wallet.opening_transfer_id;
    const abs = Math.abs(opening);
    const cur = wallet.currency;

    // Cleared out: drop the seed and remember that the answer was "nothing".
    if (abs === 0) {
      const rows = await sql`
        WITH del AS (
          UPDATE transactions SET deleted_at = NOW()
          WHERE user_id = ${userId} AND transfer_id = ${old} AND deleted_at IS NULL
        )
        UPDATE wallets SET opening_balance = 0, opening_transfer_id = NULL
        WHERE id = ${wallet.id} AND user_id = ${userId} AND deleted_at IS NULL
        RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      `;
      return (rows[0] as Wallet) || null;
    }

    const next = crypto.randomUUID();

    if (drawdown) {
      const destId = drawdown.walletId === 0 ? null : drawdown.walletId;
      const rows = await sql`
        WITH del AS (
          UPDATE transactions SET deleted_at = NOW()
          WHERE user_id = ${userId} AND transfer_id = ${old} AND deleted_at IS NULL
        ), legs AS (
          INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
          VALUES
            (${userId}, ${'Borrowed — ' + wallet.name}, ${-abs}, 'Transfer', ${cur}, ${wallet.id}, ${next}, NOW()),
            (${userId}, ${'Loan from ' + wallet.name}, ${abs}, 'Transfer', ${cur}, ${destId}, ${next}, NOW())
        )
        UPDATE wallets SET opening_balance = ${abs}, opening_transfer_id = ${next}
        WHERE id = ${wallet.id} AND user_id = ${userId} AND deleted_at IS NULL
        RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
      `;
      return (rows[0] as Wallet) || null;
    }

    const signed = isLiability ? -abs : abs;
    const title = isLiability ? 'Opening balance (amount owed)' : 'Opening balance';
    const rows = await sql`
      WITH del AS (
        UPDATE transactions SET deleted_at = NOW()
        WHERE user_id = ${userId} AND transfer_id = ${old} AND deleted_at IS NULL
      ), seed AS (
        INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
        VALUES (${userId}, ${title}, ${signed}, 'Opening Balance', ${cur}, ${wallet.id}, ${next}, NOW())
      )
      UPDATE wallets SET opening_balance = ${abs}, opening_transfer_id = ${next}
      WHERE id = ${wallet.id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
    `;
    return (rows[0] as Wallet) || null;
  }

  static async update(
    userId: string,
    id: number,
    fields: { name?: string; type?: string; currency?: string; credit_limit?: number | null },
  ): Promise<Wallet | null> {
    // credit_limit distinguishes "unchanged" (undefined) from "cleared" (null),
    // so COALESCE won't do — apply it only when provided.
    const limitProvided = fields.credit_limit !== undefined;
    const rows = await sql`
      UPDATE wallets
      SET
        name = COALESCE(${fields.name ?? null}, name),
        type = COALESCE(${fields.type !== undefined ? this.normalizeType(fields.type) : null}, type),
        currency = COALESCE(${fields.currency ?? null}, currency),
        credit_limit = CASE WHEN ${limitProvided} THEN ${fields.credit_limit ?? null}::numeric ELSE credit_limit END
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
      RETURNING id, user_id, name, type, currency, opening_balance, opening_transfer_id, credit_limit, created_at
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
      SELECT 
        wallet_id, 
        currency,
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
      GROUP BY wallet_id, currency
    `;

    const rates = await prefetchRates(preferredCurrency);

    const totals = new Map<number | null, { income: number; expense: number }>();
    for (const r of rows) {
      const walletId = (r as any).wallet_id === null ? null : Number((r as any).wallet_id);
      const cur = ((r as any).currency as string) || 'LKR';
      const rowIncome = Number((r as any).income);
      const rowExpense = Math.abs(Number((r as any).expense));

      const convertedIncome = convertSync(rowIncome, cur, preferredCurrency, rates);
      const convertedExpense = convertSync(rowExpense, cur, preferredCurrency, rates);

      const entry = totals.get(walletId) ?? { income: 0, expense: 0 };
      entry.income += convertedIncome;
      entry.expense += convertedExpense;
      totals.set(walletId, entry);
    }

    const result: WalletBalance[] = [];
    for (const w of wallets) {
      const t = totals.get(Number(w.id)) ?? { income: 0, expense: 0 };
      // The column is in the wallet's own currency; everything else here is in
      // the display currency. Convert it or every comparison against it (payoff
      // progress, the borrowed/charged split) is off by the FX rate.
      let opening: number | null = null;
      if (w.opening_balance !== null && w.opening_balance !== undefined) {
        opening = convertSync(Number(w.opening_balance), w.currency || 'LKR', preferredCurrency, rates);
      }
      // Same conversion story as opening_balance: the limit lives in the
      // wallet's currency, but "available credit" is computed against the
      // converted owed amount.
      let limit: number | null = null;
      if (w.credit_limit !== null && w.credit_limit !== undefined) {
        limit = convertSync(Number(w.credit_limit), w.currency || 'LKR', preferredCurrency, rates);
      }
      const { borrowed, charged, repaid } = liabilityBreakdown(opening, t.income, t.expense);
      result.push({
        ...w,
        opening_balance: opening,
        credit_limit: limit,
        income: t.income,
        expense: t.expense,
        balance: t.income - t.expense,
        borrowed,
        charged,
        repaid,
        display_currency: preferredCurrency,
      });
    }

    // Unassigned/legacy transactions live in a virtual default bucket (id 0).
    const unassigned = totals.get(null);
    if (unassigned && (unassigned.income !== 0 || unassigned.expense !== 0)) {
      result.unshift({
        id: 0,
        user_id: userId,
        name: 'Default',
        type: 'cash',
        currency: preferredCurrency,
        opening_balance: null,
        opening_transfer_id: null,
        credit_limit: null,
        created_at: new Date(0),
        income: unassigned.income,
        expense: unassigned.expense,
        balance: unassigned.income - unassigned.expense,
        // The default bucket is an asset with no seed, so nothing was borrowed
        // and every outflow is a real charge.
        borrowed: 0,
        charged: unassigned.expense,
        repaid: unassigned.income,
        display_currency: preferredCurrency,
      });
    }
    return result;
  }

  /**
   * Moves money between two wallets as a pair of transactions (−from / +to)
   * sharing one transfer uuid. Wallet id 0 = the virtual default bucket
   * (wallet_id NULL). Both legs use [currency] so they cancel exactly in
   * converted totals.
   *
   * Both legs go in ONE multi-row INSERT: a single statement is atomic even on
   * Neon's HTTP driver, so a half-written transfer can't exist. Two separate
   * inserts had no safe ordering — whichever leg lands first is wrong in some
   * direction (− first understates a balance; for a loan drawdown − first
   * instead overstates the debt and sinks net worth, while + first invents
   * cash).
   *
   * [titles] overrides the generic wording for flows where "Transfer to X"
   * misdescribes what happened — a loan drawdown, say.
   */
  static async transfer(
    userId: string,
    fromWalletId: number,
    toWalletId: number,
    amount: number,
    currency: string,
    fromName: string,
    toName: string,
    titles?: { from: string; to: string },
  ): Promise<{ transferId: string }> {
    const transferId = crypto.randomUUID();
    const fromId = fromWalletId === 0 ? null : fromWalletId;
    const toId = toWalletId === 0 ? null : toWalletId;
    const abs = Math.abs(amount);
    const fromTitle = titles?.from ?? 'Transfer to ' + toName;
    const toTitle = titles?.to ?? 'Transfer from ' + fromName;

    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES
        (${userId}, ${fromTitle}, ${-abs}, 'Transfer', ${currency}, ${fromId}, ${transferId}, NOW()),
        (${userId}, ${toTitle}, ${abs}, 'Transfer', ${currency}, ${toId}, ${transferId}, NOW())
    `;
    return { transferId };
  }

  /**
   * Records a wallet ↔ goal money movement as a single transfer-excluded
   * transaction (so it never counts as spending/income in analytics).
   * `signedAmount` < 0 → money left the wallet to fund a goal; > 0 → money
   * returned to the wallet from a withdrawal. Wallet id 0/NULL = default bucket.
   */
  static async recordGoalMovement(
    userId: string,
    walletId: number | null,
    signedAmount: number,
    currency: string,
    goalName: string,
  ): Promise<void> {
    const wallet = walletId && walletId > 0 ? walletId : null;
    const title = signedAmount < 0 ? `Saved to ${goalName}` : `Withdrew from ${goalName}`;
    const transferId = crypto.randomUUID();
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${title}, ${signedAmount}, 'Goal Savings', ${currency}, ${wallet}, ${transferId}, NOW())
    `;
  }

  // NOTE: opening-balance seeds are written inline by createWithOpening /
  // replaceOpening (atomically, alongside the wallet columns). Don't add a
  // standalone seed helper — a second write path is how double-seeding starts.

  /**
   * What the user can actually spend right now, in their display currency.
   *
   * Built on `balances()` so the dashboard headline is consistent-by-
   * construction with the wallet cards and net worth — all three then read the
   * same rows through the same conversion and the same asset/liability split.
   */
  static async moneyOnHand(userId: string, preferredCurrency: string): Promise<number> {
    const balances = await this.balances(userId, preferredCurrency);
    return foldMoneyOnHand(
      balances.map((b) => ({ isLiability: LIABILITY_TYPES.has(b.type), balance: b.balance })),
    );
  }

  /**
   * Money on hand at the end of each of the last [months] months.
   *
   * Computed server-side because the client can't: its TransactionModel carries
   * no transfer_id and no wallet type, so it can't tell a transfer leg from a
   * real expense or debt from cash — and it only ever holds the most recent page
   * of transactions, so any running total it folds starts from a fictional zero.
   *
   * Same rows and same asset/liability split as `moneyOnHand`, so the last point
   * always equals the dashboard headline.
   */
  static async moneyOnHandHistory(
    userId: string,
    preferredCurrency: string,
    months = 6,
  ): Promise<Array<{ month: string; balance: number }>> {
    const wallets = await this.listByUser(userId);
    const typeOf = new Map(wallets.map((w) => [Number(w.id), w.type]));

    const rows = await sql`
      SELECT 
        wallet_id, 
        currency,
        DATE_TRUNC('month', created_at) as month_date,
        SUM(amount) as net_amount
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
      GROUP BY wallet_id, currency, DATE_TRUNC('month', created_at)
    `;

    const rates = await prefetchRates(preferredCurrency);

    const monthAggregates: Array<{ walletId: number | null; monthStr: string; amount: number }> = [];
    for (const r of rows) {
      const raw = Number((r as any).net_amount);
      const cur = ((r as any).currency as string) || 'LKR';
      const amount = convertSync(raw, cur, preferredCurrency, rates);
      
      const rawDate = (r as any).month_date;
      const d = rawDate instanceof Date ? rawDate : new Date(rawDate);
      const monthStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      
      monthAggregates.push({
        walletId: (r as any).wallet_id === null ? null : Number((r as any).wallet_id),
        monthStr,
        amount
      });
    }

    const now = new Date();
    const points: Array<{ month: string; balance: number }> = [];
    for (let i = months - 1; i >= 0; i--) {
      const target = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const targetMonthStr = `${target.getFullYear()}-${String(target.getMonth() + 1).padStart(2, '0')}`;

      const perWallet = new Map<number | null, number>();
      for (const agg of monthAggregates) {
        if (agg.monthStr <= targetMonthStr) {
          perWallet.set(agg.walletId, (perWallet.get(agg.walletId) ?? 0) + agg.amount);
        }
      }

      points.push({
        month: targetMonthStr,
        balance: foldMoneyOnHand(
          [...perWallet.entries()].map(([id, balance]) => ({
            // Unassigned rows sit in the default bucket, which is cash.
            isLiability: id !== null && LIABILITY_TYPES.has(typeOf.get(id) ?? 'cash'),
            balance,
          })),
        ),
      });
    }
    return points;
  }

  /**
   * Records the cash side of an IOU as a single transfer-excluded transaction:
   * lending money out (−), being repaid (+), borrowing (+), repaying (−).
   *
   * Transfer-tagged because none of these are earning or spending — they're a
   * receivable/payable changing form. Recording an IOU settlement as plain
   * income was exactly the bug this replaces: every repaid loan inflated
   * lifetime earnings. Net worth stays flat by construction — the wallet moves
   * one way while the open-debt side (counted in netWorth) moves the other.
   * Wallet id 0/NULL = the default bucket.
   */
  static async recordDebtMovement(
    userId: string,
    walletId: number | null,
    signedAmount: number,
    currency: string,
    title: string,
  ): Promise<void> {
    const wallet = walletId && walletId > 0 ? walletId : null;
    const transferId = crypto.randomUUID();
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${title}, ${signedAmount}, 'IOU', ${currency}, ${wallet}, ${transferId}, NOW())
    `;
  }

  /**
   * The cash side of a group settle-up: one transfer-excluded leg — the payer's
   * wallet out (−) or the payee's in (+) — tagged with the SHARED [transferId]
   * (both legs of one settlement share it) so an undo can delete the pair.
   *
   * Transfer-tagged for the same reason as an IOU: settling a shared debt is a
   * receivable/payable changing form, not earning or spending. Net worth stays
   * flat because the group position (counted in netWorth) moves the other way.
   * Wallet id 0/NULL = the default cash bucket — where the payee's side always
   * lands, since we don't know their wallets.
   */
  static async recordGroupSettleMovement(
    userId: string,
    walletId: number | null,
    signedAmount: number,
    currency: string,
    title: string,
    transferId: string,
  ): Promise<void> {
    const wallet = walletId && walletId > 0 ? walletId : null;
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${title}, ${signedAmount}, 'Group Settle', ${currency}, ${wallet}, ${transferId}, NOW())
    `;
  }

  /**
   * Removes transfer legs by their shared transfer_id, scoped to [userIds] (both
   * sides of a group settle-up). Undoing a settlement reverses its cash movement.
   */
  static async deleteByTransferId(userIds: string[], transferId: string): Promise<void> {
    await sql`
      DELETE FROM transactions
      WHERE transfer_id = ${transferId} AND user_id::text = ANY(${userIds}::text[])
    `;
  }

  /** A single wallet's balance in the preferred currency (0 = default bucket). */
  static async balanceOf(userId: string, walletId: number, preferredCurrency: string): Promise<number> {
    const balances = await this.balances(userId, preferredCurrency);
    const match = balances.find((b) => Number(b.id) === Number(walletId));
    return match ? match.balance : 0;
  }

  /**
   * Records a goal being SPENT (withdraw-as-expense) as a balanced pair on the
   * default bucket: a transfer-excluded income (`+amount`, the goal money
   * arriving — invisible to analytics) and a real expense (`-amount`, the actual
   * spend — counted in analytics). Net wallet effect is zero, so net worth drops
   * only via the goal's own decrease (no double count) while the spend still
   * shows up in the spending report / heatmap.
   */
  static async recordGoalSpend(
    userId: string,
    amount: number,
    currency: string,
    goalName: string,
    category: string,
  ): Promise<void> {
    const abs = Math.abs(amount);
    const transferId = crypto.randomUUID();
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${'From ' + goalName + ' goal'}, ${abs}, 'Goal Savings', ${currency}, NULL, ${transferId}, NOW())
    `;
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id, transfer_id, created_at)
      VALUES (${userId}, ${'Spent from ' + goalName}, ${-abs}, ${category}, ${currency}, NULL, NULL, NOW())
    `;
  }

  /**
   * Net worth = assets − liabilities, in the user's display currency.
   * Asset wallets (cash/bank/investment + the default bucket) contribute their
   * balance; liability wallets (credit/card/loan) contribute how much is OWED,
   * or — when overpaid — the credit sitting in the user's favour. See
   * netWorthContribution for why the overpaid case can't collapse to zero.
   */
  static async netWorth(userId: string, preferredCurrency: string) {
    const balances = await this.balances(userId, preferredCurrency);

    let assets = 0;
    let liabilities = 0;
    const byType = new Map<string, { type: string; total: number; isLiability: boolean }>();

    for (const b of balances) {
      const isLiability = LIABILITY_TYPES.has(b.type);
      const { asset, liability } = netWorthContribution(isLiability, b.balance);
      assets += asset;
      liabilities += liability;

      // One wallet type can land on both sides at once (a card that's owing and
      // another that's overpaid), so debt and credit are keyed separately —
      // otherwise they'd cancel into a single misleading figure.
      const onDebtSide = isLiability && b.balance <= 0;
      const key = `${b.type}|${onDebtSide ? 'debt' : 'asset'}`;
      const entry = byType.get(key) ?? { type: b.type, total: 0, isLiability: onDebtSide };
      entry.total += onDebtSide ? liability : asset;
      byType.set(key, entry);
    }

    const rates = await prefetchRates(preferredCurrency);

    // Savings goals are money set aside — still the user's asset. Counting them
    // keeps wallet→goal funding net-worth-neutral (wallet drops, goals rise).
    // Group goals owned by others are excluded (user_id filter).
    const goalRows = await sql`
      SELECT current_amount, currency FROM goals
      WHERE user_id = ${userId} AND deleted_at IS NULL
    `;
    let goalSavings = 0;
    for (const g of goalRows) {
      const amt = Number((g as any).current_amount);
      const cur = String((g as any).currency || 'LKR');
      goalSavings += convertSync(amt, cur, preferredCurrency, rates);
    }
    // Money the user put into group goals OWNED BY OTHERS. Their wallet was
    // debited (contributeToGoal moves real money) but the goal above is counted
    // under the owner only — without this the contributor's net worth drops by
    // every shared-goal contribution as if the money were spent. Summed from
    // the per-contributor timeline, per goal-currency, and clamped at zero (a
    // member can in principle withdraw more than they put in).
    const sharedRows = await sql`
      SELECT g.currency, COALESCE(SUM(c.amount), 0) AS total
      FROM goal_contributions c
      INNER JOIN goals g ON g.id = c.goal_id
      WHERE c.user_id = ${userId}
        AND g.user_id != ${userId}
        AND g.group_id IS NOT NULL
        AND g.deleted_at IS NULL
      GROUP BY g.currency
    `;
    let sharedSavings = 0;
    for (const r of sharedRows) {
      const raw = Number((r as any).total);
      const cur = String((r as any).currency || 'LKR');
      sharedSavings += convertSync(raw, cur, preferredCurrency, rates);
    }
    goalSavings += Math.max(0, sharedSavings);

    if (goalSavings > 0) {
      assets += goalSavings;
      byType.set('goals|asset', { type: 'goals', total: goalSavings, isLiability: false });
    }

    // Open IOUs are real money positions: what others owe the user is a
    // receivable (asset), what the user owes is a payable (liability). Counting
    // them keeps the settle flow net-worth-neutral — the wallet moves one way
    // while the open debt disappears the other.
    const debtRows = await sql`
      SELECT amount, currency, direction FROM debts
      WHERE user_id = ${userId} AND status = 'open' AND deleted_at IS NULL
    `;
    let receivable = 0;
    let payable = 0;
    for (const d of debtRows) {
      const raw = Number((d as any).amount);
      const cur = String((d as any).currency || 'LKR');
      const amt = convertSync(raw, cur, preferredCurrency, rates);

      if (String((d as any).direction) === 'i_owe') payable += amt;
      else receivable += amt;
    }
    if (receivable > 0) {
      assets += receivable;
      byType.set('iou_receivable|asset', { type: 'iou_receivable', total: receivable, isLiability: false });
    }
    if (payable > 0) {
      liabilities += payable;
      byType.set('iou_payable|debt', { type: 'iou_payable', total: payable, isLiability: true });
    }

    // Group (Splitwise-lite) positions are real money too. A net-creditor member
    // is owed by the group — a receivable (asset); a net-debtor owes it — a
    // payable (liability). Counting them keeps a settle-up net-worth-neutral: the
    // wallet moves one way (recordGroupSettleMovement) while this open position
    // moves the other, exactly like the IOUs above. Without this a group payer's
    // net worth dropped by the FULL expense instead of just their share, and a
    // debtor's didn't drop at all.
    const { GroupModel } = await import('./GroupModel');
    const groupNet = await GroupModel.userGroupNet(userId, preferredCurrency);
    if (groupNet.receivable > 0) {
      assets += groupNet.receivable;
      byType.set('group_receivable|asset', { type: 'group_receivable', total: groupNet.receivable, isLiability: false });
    }
    if (groupNet.payable > 0) {
      liabilities += groupNet.payable;
      byType.set('group_payable|debt', { type: 'group_payable', total: groupNet.payable, isLiability: true });
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
