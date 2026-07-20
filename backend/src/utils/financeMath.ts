/**
 * Pure finance-math helpers, extracted from GroupModel / transactionsController
 * so the money-critical logic is unit-testable without a database.
 * All amounts arriving here are already converted to the display currency.
 */

/**
 * Largest value the money columns can hold: every amount in the schema is
 * `DECIMAL(10,2)`. Validators MUST reject above this — Postgres raises a numeric
 * overflow on insert, which surfaces as a 500 *after* earlier statements in the
 * request have already committed (e.g. a wallet row with no opening-balance
 * seed, which then renders as "100% paid off"). A clean 400 is the only safe
 * outcome.
 */
export const MAX_AMOUNT = 99_999_999.99;

// ── CSV escaping ─────────────────────────────────────────────────────────────

/** Escapes a single CSV cell per RFC 4180 (quote if it contains "," '"' or newline). */
export function csvCell(value: unknown): string {
  const s = value === null || value === undefined ? '' : String(value);
  if (/[",\n\r]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

// ── Bulk-import row sanitization ─────────────────────────────────────────────

export interface SanitizedImportRow {
  title: string;
  amount: number;
  category: string;
  created_at: string; // YYYY-MM-DD
  currency: string;
  client_op_id: string | null;
}

/**
 * Validates and normalizes raw bulk-import rows. Invalid rows (missing title,
 * non-finite/zero/absurd amounts, malformed dates) are counted as skipped, not
 * rejected wholesale — imports are best-effort per row.
 */
export function sanitizeImportRows(rows: unknown[]): { valid: SanitizedImportRow[]; skipped: number } {
  const valid: SanitizedImportRow[] = [];
  let skipped = 0;

  for (const raw of rows) {
    const row = raw as any;
    const title = typeof row?.title === 'string' ? row.title.trim().slice(0, 200) : '';
    const amount = Number(row?.amount);
    const category =
      typeof row?.category === 'string' && row.category.trim() ? row.category.trim().slice(0, 255) : 'Imported';
    const created_at = typeof row?.created_at === 'string' ? row.created_at : '';
    const currency =
      typeof row?.currency === 'string' && row.currency.trim() ? row.currency.trim().toUpperCase().slice(0, 10) : 'LKR';
    const client_op_id =
      typeof row?.client_op_id === 'string' && row.client_op_id.trim() ? row.client_op_id.trim().slice(0, 64) : null;

    const validDate = /^\d{4}-\d{2}-\d{2}$/.test(created_at);
    if (!title || !Number.isFinite(amount) || amount === 0 || Math.abs(amount) > MAX_AMOUNT || !validDate) {
      skipped++;
      continue;
    }

    valid.push({
      title,
      amount: Math.round(amount * 100) / 100,
      category,
      created_at,
      currency,
      client_op_id,
    });
  }

  return { valid, skipped };
}

// ── Net worth ────────────────────────────────────────────────────────────────

/**
 * Splits one wallet's balance into what it contributes to assets vs liabilities.
 *
 * Liability wallets (credit/card/loan) hold debt: charges drive the balance
 * negative and that negative IS what's owed. But a liability can also go
 * POSITIVE — an overpaid card, an extra loan payment, a refund larger than the
 * charges. That credit is money in the user's favour, so it counts as an asset.
 * Treating it as zero instead makes an overpayment silently shrink net worth:
 * the paying wallet drops and nothing offsets it, so a net-worth-neutral
 * transfer would appear to destroy money.
 *
 * Asset wallets pass their balance through as-is, negative included — an
 * overdrawn account genuinely lowers net worth.
 */
export function netWorthContribution(
  isLiability: boolean,
  balance: number,
): { asset: number; liability: number } {
  if (!isLiability) return { asset: balance, liability: 0 };
  if (balance > 0) return { asset: balance, liability: 0 };
  // Math.abs rather than -balance: negating a 0 balance yields -0, which leaks
  // into JSON and formatting as "-0".
  return { asset: 0, liability: Math.abs(balance) };
}

/**
 * Money the user actually has: every asset wallet's balance, plus any credit
 * sitting on an overpaid debt account. Debt itself is excluded — you can't
 * spend what you owe — and so are savings goals, whose money has already left
 * the wallet it was funded from.
 *
 * This is deliberately NOT net worth: net worth subtracts debt and adds goals.
 * "How much can I spend" and "what am I worth" are different questions.
 *
 * Balances must already be in one currency.
 */
export function moneyOnHand(wallets: Array<{ isLiability: boolean; balance: number }>): number {
  let total = 0;
  for (const w of wallets) {
    total += netWorthContribution(w.isLiability, w.balance).asset;
  }
  return Math.round(total * 100) / 100;
}

/**
 * Splits a liability wallet's totals into the three flows a debt actually has,
 * so "owe 105,000" is traceable: `borrowed + charged − repaid = owed`.
 *
 * `expense` lumps the opening seed in with real charges, because `balances()`
 * classifies by sign alone and the seed is negative — so a loan opened at
 * 100,000 and spent on once reads "charged 105,000", which is not what the user
 * did. Subtracting the seed back out separates the two.
 *
 * `repaid` is `income` rather than non-transfer income: repayments arrive as the
 * `+` leg of a transfer, and `balances()` deliberately counts transfer legs.
 *
 * All three arguments must already be in the SAME currency — mixing a converted
 * `expense` with a raw `opening` silently scales the result by the FX rate.
 */
export function liabilityBreakdown(
  opening: number | null,
  income: number,
  expense: number,
): { borrowed: number; charged: number; repaid: number } {
  const borrowed = opening && opening > 0 ? opening : 0;
  return {
    borrowed,
    // Clamped: rounding on a fully-seeded, never-charged wallet otherwise
    // surfaces as "charged -0".
    charged: Math.max(0, expense - borrowed),
    repaid: income,
  };
}

// ── Group balance math (Splitwise-lite) ──────────────────────────────────────

export interface BalanceMember {
  user_id: string;
  name: string;
}

/** One shared expense, amount already positive and currency-converted. */
export interface BalanceExpense {
  user_id: string;
  amount: number;
}

/** One recorded settlement ("from paid to"), amount already converted. */
export interface BalanceSettlement {
  from: string;
  to: string;
  amount: number;
}

export interface MemberBalance {
  user_id: string;
  name: string;
  paid: number;
  net: number; // > 0 → gets money back; < 0 → owes
}

export interface SettleSuggestion {
  from: string;
  from_name: string;
  to: string;
  to_name: string;
  amount: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Equal-split balances over shared expenses, adjusted by settlements, plus a
 * greedy minimal-transfer suggestion list ("biggest debtor pays biggest
 * creditor"). Nets always sum to ~0 and suggestions fully cover the debts.
 */
export function computeBalances(
  members: BalanceMember[],
  expenses: BalanceExpense[],
  settlements: BalanceSettlement[],
): { members: MemberBalance[]; suggestions: SettleSuggestion[]; total: number } {
  if (members.length === 0) return { members: [], suggestions: [], total: 0 };

  const paidBy = new Map<string, number>();
  let total = 0;
  for (const e of expenses) {
    paidBy.set(e.user_id, (paidBy.get(e.user_id) ?? 0) + e.amount);
    total += e.amount;
  }

  const fairShare = total / members.length;
  const net = new Map<string, number>();
  for (const m of members) {
    net.set(m.user_id, (paidBy.get(m.user_id) ?? 0) - fairShare);
  }

  // Settlements: the payer's debt shrinks (net up), the receiver's credit
  // shrinks (net down). Amounts to/from non-members are ignored.
  for (const s of settlements) {
    if (net.has(s.from)) net.set(s.from, net.get(s.from)! + s.amount);
    if (net.has(s.to)) net.set(s.to, net.get(s.to)! - s.amount);
  }

  const result: MemberBalance[] = members.map((m) => ({
    user_id: m.user_id,
    name: m.name,
    paid: round2(paidBy.get(m.user_id) ?? 0),
    net: round2(net.get(m.user_id) ?? 0),
  }));

  // Greedy transfer suggestions: biggest debtor pays biggest creditor.
  const debtors = result.filter((r) => r.net < -0.01).map((r) => ({ ...r, left: -r.net })).sort((a, b) => b.left - a.left);
  const creditors = result.filter((r) => r.net > 0.01).map((r) => ({ ...r, left: r.net })).sort((a, b) => b.left - a.left);
  const suggestions: SettleSuggestion[] = [];
  let di = 0;
  let ci = 0;
  while (di < debtors.length && ci < creditors.length) {
    const pay = Math.min(debtors[di].left, creditors[ci].left);
    suggestions.push({
      from: debtors[di].user_id,
      from_name: debtors[di].name,
      to: creditors[ci].user_id,
      to_name: creditors[ci].name,
      amount: round2(pay),
    });
    debtors[di].left -= pay;
    creditors[ci].left -= pay;
    if (debtors[di].left <= 0.01) di++;
    if (creditors[ci].left <= 0.01) ci++;
  }

  return { members: result, suggestions, total: round2(total) };
}
