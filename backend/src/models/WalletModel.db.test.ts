import 'dotenv/config';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import type { WalletModel as WalletModelClass } from './WalletModel';
import { MAX_AMOUNT } from '../utils/financeMath';

/**
 * The wallet money paths, executed against a real database.
 *
 * Everything else in this suite is a pure function, which is precisely how a
 * production 500 got shipped: `tsc` can't see inside a SQL template string, and
 * a unit test never runs the statement. `INSERT ... SELECT` sends its parameters
 * untyped (unlike `INSERT ... VALUES`, which infers them from the target column),
 * so an uncast number arrived as `text` and Postgres rejected it — invisible to
 * typecheck and to all 84 pure tests.
 *
 * Isolation is by `user_id`: every query in WalletModel is scoped to one, so a
 * random test user can't see or touch real data, and afterAll removes it. Skips
 * cleanly when there's no DATABASE_URL, so a checkout without .env still passes.
 *
 * All amounts are LKR — getRate short-circuits to 1 for same-currency, so these
 * never depend on the exchange-rate API.
 */
const hasDb = !!process.env.DATABASE_URL;

describe.skipIf(!hasDb)('WalletModel (real database)', () => {
  let sql: (typeof import('../config/db'))['sql'];
  let WalletModel: typeof WalletModelClass;
  let GoalModel: (typeof import('./GoalModel'))['GoalModel'];
  let DebtModel: (typeof import('./DebtModel'))['DebtModel'];

  const USER = `__test_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  let seq = 0;
  /** Wallet names are unique per user, so every test needs its own. */
  const name = (base: string) => `${base}-${++seq}`;

  beforeAll(async () => {
    // Imported lazily: db.ts calls neon(DATABASE_URL) at module load, which
    // would throw at import time on a checkout without one — even when skipped.
    ({ sql } = await import('../config/db'));
    ({ WalletModel } = await import('./WalletModel'));
    ({ GoalModel } = await import('./GoalModel'));
    ({ DebtModel } = await import('./DebtModel'));
  });

  afterAll(async () => {
    if (!sql) return;
    await sql`DELETE FROM transactions WHERE user_id = ${USER}`;
    await sql`DELETE FROM goal_contributions WHERE goal_id IN (SELECT id FROM goals WHERE user_id = ${USER})`;
    await sql`DELETE FROM goals WHERE user_id = ${USER}`;
    await sql`DELETE FROM debts WHERE user_id = ${USER}`;
    await sql`DELETE FROM wallets WHERE user_id = ${USER}`;
  });

  /** The legs written under one transfer uuid, cheapest first. */
  async function legs(transferId: string) {
    const rows = await sql`
      SELECT wallet_id, amount FROM transactions
      WHERE user_id = ${USER} AND transfer_id = ${transferId} AND deleted_at IS NULL
      ORDER BY amount ASC
    `;
    return rows.map((r: any) => ({
      walletId: r.wallet_id === null ? null : Number(r.wallet_id),
      amount: Number(r.amount),
    }));
  }

  const balanceOf = async (walletName: string) => {
    const all = await WalletModel.balances(USER, 'LKR');
    return all.find((b) => b.name === walletName)!;
  };

  describe('createWithOpening', () => {
    it('seeds an asset wallet with the money already in it', async () => {
      const w = await WalletModel.createWithOpening(USER, name('Bank'), 'bank', 'LKR', 50_000);
      expect(Number(w.opening_balance)).toBe(50_000);
      expect(w.opening_transfer_id).toBeTruthy();
      expect(await legs(w.opening_transfer_id!)).toEqual([
        { walletId: Number(w.id), amount: 50_000 },
      ]);
    });

    it('seeds a debt already spent as a single negative leg', async () => {
      const w = await WalletModel.createWithOpening(USER, name('Card'), 'credit', 'LKR', 8_000);
      expect(await legs(w.opening_transfer_id!)).toEqual([
        { walletId: Number(w.id), amount: -8_000 },
      ]);
    });

    it('records a drawdown as debt here and cash there', async () => {
      const bankName = name('Bank');
      const bank = await WalletModel.createWithOpening(USER, bankName, 'bank', 'LKR', 0);
      const loan = await WalletModel.createWithOpening(USER, name('Loan'), 'loan', 'LKR', 100_000, {
        walletId: Number(bank.id),
        walletName: bankName,
      });

      // One uuid, two legs — the debt and the money it produced.
      expect(await legs(loan.opening_transfer_id!)).toEqual([
        { walletId: Number(loan.id), amount: -100_000 },
        { walletId: Number(bank.id), amount: 100_000 },
      ]);
      expect(Number(loan.opening_balance)).toBe(100_000);
    });

    it('can draw down into the default bucket (wallet id 0 → NULL)', async () => {
      const loan = await WalletModel.createWithOpening(USER, name('Loan'), 'loan', 'LKR', 5_000, {
        walletId: 0,
        walletName: 'Default',
      });
      const rows = await legs(loan.opening_transfer_id!);
      expect(rows.find((r) => r.amount > 0)!.walletId).toBeNull();
    });

    it('accepts the largest amount the column can hold', async () => {
      // The validators allowed 1e9 against a DECIMAL(10,2) column, so a big but
      // real loan used to insert the wallet and then throw on the seed.
      const w = await WalletModel.createWithOpening(USER, name('Big'), 'loan', 'LKR', MAX_AMOUNT);
      expect(await legs(w.opening_transfer_id!)).toEqual([
        { walletId: Number(w.id), amount: -MAX_AMOUNT },
      ]);
    });
  });

  describe('what the user ends up seeing', () => {
    it('leaves borrowed money spendable and the debt outstanding', async () => {
      const bankName = name('Bank');
      const loanName = name('Loan');
      const bank = await WalletModel.createWithOpening(USER, bankName, 'bank', 'LKR', 50_000);
      await WalletModel.createWithOpening(USER, loanName, 'loan', 'LKR', 100_000, {
        walletId: Number(bank.id),
        walletName: bankName,
      });

      // The cash landed in the bank; the loan still owes all of it.
      expect((await balanceOf(bankName)).balance).toBe(150_000);
      expect((await balanceOf(loanName)).balance).toBe(-100_000);

      const loan = await balanceOf(loanName);
      expect(loan.amountOwed ?? -loan.balance).toBe(100_000);
      // The seed is not something the user "charged".
      expect([loan.borrowed, loan.charged, loan.repaid]).toEqual([100_000, 0, 0]);
    });

    it('separates a real charge from the opening debt', async () => {
      const cardName = name('Card');
      const card = await WalletModel.createWithOpening(USER, cardName, 'credit', 'LKR', 10_000);
      await sql`
        INSERT INTO transactions (user_id, title, amount, category, currency, wallet_id)
        VALUES (${USER}, 'Groceries', -2500, 'Food', 'LKR', ${Number(card.id)})
      `;

      const b = await balanceOf(cardName);
      expect(b.balance).toBe(-12_500);
      expect([b.borrowed, b.charged, b.repaid]).toEqual([10_000, 2_500, 0]);
    });

    it('keeps borrowing net-worth-neutral and off the money-on-hand total', async () => {
      const user = `${USER}_nw`;
      try {
        const bank = await WalletModel.createWithOpening(user, 'Bank', 'bank', 'LKR', 50_000);
        await WalletModel.createWithOpening(user, 'Loan', 'loan', 'LKR', 100_000, {
          walletId: Number(bank.id),
          walletName: 'Bank',
        });

        // Richer by nothing: the cash is real, and so is the debt.
        const nw = await WalletModel.netWorth(user, 'LKR');
        expect(nw.netWorth).toBe(50_000);
        expect(nw.assets).toBe(150_000);
        expect(nw.liabilities).toBe(100_000);

        // But it IS spendable, which is what the headline claims to show.
        expect(await WalletModel.moneyOnHand(user, 'LKR')).toBe(150_000);
      } finally {
        await sql`DELETE FROM transactions WHERE user_id = ${user}`;
        await sql`DELETE FROM wallets WHERE user_id = ${user}`;
      }
    });
  });

  describe('replaceOpening', () => {
    it('replaces the seed rather than stacking an adjustment on top', async () => {
      const n = name('Bank');
      const w = await WalletModel.createWithOpening(USER, n, 'bank', 'LKR', 50_000);
      const first = w.opening_transfer_id!;

      const updated = await WalletModel.replaceOpening(USER, w, 30_000);
      expect(Number(updated!.opening_balance)).toBe(30_000);
      expect(updated!.opening_transfer_id).not.toBe(first);

      // Old leg gone (soft-deleted), not left behind alongside the new one.
      expect(await legs(first)).toEqual([]);
      expect((await balanceOf(n)).balance).toBe(30_000);
    });

    it('clears the seed when corrected to zero', async () => {
      const n = name('Card');
      const w = await WalletModel.createWithOpening(USER, n, 'credit', 'LKR', 8_000);
      const updated = await WalletModel.replaceOpening(USER, w, 0);

      expect(Number(updated!.opening_balance)).toBe(0);
      expect(updated!.opening_transfer_id).toBeNull();
      expect((await balanceOf(n)).balance).toBe(0);
    });

    it('replaces both legs of a drawdown', async () => {
      const bankName = name('Bank');
      const loanName = name('Loan');
      const bank = await WalletModel.createWithOpening(USER, bankName, 'bank', 'LKR', 0);
      const loan = await WalletModel.createWithOpening(USER, loanName, 'loan', 'LKR', 100_000, {
        walletId: Number(bank.id),
        walletName: bankName,
      });

      const updated = await WalletModel.replaceOpening(USER, loan, 60_000, {
        walletId: Number(bank.id),
        walletName: bankName,
      });

      expect(await legs(loan.opening_transfer_id!)).toEqual([]);
      expect(await legs(updated!.opening_transfer_id!)).toEqual([
        { walletId: Number(loan.id), amount: -60_000 },
        { walletId: Number(bank.id), amount: 60_000 },
      ]);
      expect((await balanceOf(bankName)).balance).toBe(60_000);
    });

    it('seeds a legacy wallet that never had an opening recorded', async () => {
      const n = name('Legacy');
      const w = await WalletModel.create(USER, n, 'bank', 'LKR', null);
      expect(w.opening_transfer_id).toBeNull();

      // Nothing to delete — transfer_id = NULL matches no row — so this just adds.
      const updated = await WalletModel.replaceOpening(USER, w, 25_000);
      expect((await balanceOf(n)).balance).toBe(25_000);
      expect(updated!.opening_transfer_id).toBeTruthy();
    });
  });

  describe('transfer', () => {
    it('writes both legs under one uuid', async () => {
      const aName = name('A');
      const bName = name('B');
      const a = await WalletModel.createWithOpening(USER, aName, 'cash', 'LKR', 10_000);
      const b = await WalletModel.createWithOpening(USER, bName, 'bank', 'LKR', 0);

      const { transferId } = await WalletModel.transfer(
        USER, Number(a.id), Number(b.id), 4_000, 'LKR', aName, bName,
      );

      expect(await legs(transferId)).toEqual([
        { walletId: Number(a.id), amount: -4_000 },
        { walletId: Number(b.id), amount: 4_000 },
      ]);
      expect((await balanceOf(aName)).balance).toBe(6_000);
      expect((await balanceOf(bName)).balance).toBe(4_000);
    });

    it('repaying a loan lowers the debt without touching earnings', async () => {
      const bankName = name('Bank');
      const loanName = name('Loan');
      const bank = await WalletModel.createWithOpening(USER, bankName, 'bank', 'LKR', 50_000);
      const loan = await WalletModel.createWithOpening(USER, loanName, 'loan', 'LKR', 100_000);

      await WalletModel.transfer(
        USER, Number(bank.id), Number(loan.id), 10_000, 'LKR', bankName, loanName,
      );

      const b = await balanceOf(loanName);
      expect(b.balance).toBe(-90_000);
      // Repayments arrive as a transfer's + leg, which balances() counts.
      expect(b.repaid).toBe(10_000);
      expect((await balanceOf(bankName)).balance).toBe(40_000);
    });
  });

  describe('credit limit', () => {
    it('stores the limit on create and converts it in balances()', async () => {
      const n = name('Card');
      const w = await WalletModel.createWithOpening(USER, n, 'credit', 'LKR', 0, undefined, 50_000);
      expect(Number(w.credit_limit)).toBe(50_000);

      const all = await WalletModel.balances(USER, 'LKR');
      const b = all.find((x) => x.name === n)!;
      expect(b.credit_limit).toBe(50_000);
    });

    it('sets and clears the limit through update (CASE WHEN + cast shape)', async () => {
      // update()'s credit_limit branch is a CASE WHEN with a ::numeric cast —
      // a statement shape typecheck can't validate, hence a real execution.
      const w = await WalletModel.createWithOpening(USER, name('Card'), 'card', 'LKR', 0);
      const withLimit = await WalletModel.update(USER, Number(w.id), { credit_limit: 25_000 });
      expect(Number(withLimit!.credit_limit)).toBe(25_000);

      const untouched = await WalletModel.update(USER, Number(w.id), { name: 'Renamed-' + w.id });
      expect(Number(untouched!.credit_limit)).toBe(25_000);

      const cleared = await WalletModel.update(USER, Number(w.id), { credit_limit: null });
      expect(cleared!.credit_limit).toBeNull();
    });
  });

  describe('IOUs', () => {
    it('writes a transfer-tagged leg that never touches income/expense analytics', async () => {
      const n = name('Bank');
      const bank = await WalletModel.createWithOpening(USER, n, 'bank', 'LKR', 10_000);
      await WalletModel.recordDebtMovement(USER, Number(bank.id), -4_000, 'LKR', 'Lent to Nimal');

      const b = (await WalletModel.balances(USER, 'LKR')).find((x) => x.name === n)!;
      expect(b.balance).toBe(6_000); // the cash left
      // Transfer-tagged: the analytics classification (borrowed/charged/repaid
      // aside, which reads raw expense) — verify the row carries a transfer_id.
      const rows = await sql`
        SELECT transfer_id, category FROM transactions
        WHERE user_id = ${USER} AND title = 'Lent to Nimal'
      `;
      expect((rows[0] as any).transfer_id).toBeTruthy();
      expect((rows[0] as any).category).toBe('IOU');
    });

    it('counts open IOUs in net worth, and settling is net-worth-neutral', async () => {
      const user = `${USER}_iou`;
      try {
        const bank = await WalletModel.createWithOpening(user, 'Bank', 'bank', 'LKR', 50_000);

        // Lend 5,000 from the bank: cash −5,000, receivable +5,000 → flat.
        const { debt } = await DebtModel.create(user, 'Nimal', 5_000, 'LKR', 'owed_to_me');
        await WalletModel.recordDebtMovement(user, Number(bank.id), -5_000, 'LKR', 'Lent to Nimal');

        let nw = await WalletModel.netWorth(user, 'LKR');
        expect(nw.netWorth).toBe(50_000);
        expect(nw.byType.find((t) => t.type === 'iou_receivable')?.total).toBe(5_000);

        // Repaid into the bank: cash +5,000, receivable gone → still flat.
        const settled = await DebtModel.settle(user, Number(debt.id));
        expect(settled).not.toBeNull();
        await WalletModel.recordDebtMovement(user, Number(bank.id), 5_000, 'LKR', 'Repaid by Nimal');

        nw = await WalletModel.netWorth(user, 'LKR');
        expect(nw.netWorth).toBe(50_000);
        expect(nw.byType.find((t) => t.type === 'iou_receivable')).toBeUndefined();

        // Settle is one-shot: a replay finds nothing open and must not fire
        // another movement.
        expect(await DebtModel.settle(user, Number(debt.id))).toBeNull();
      } finally {
        await sql`DELETE FROM transactions WHERE user_id = ${user}`;
        await sql`DELETE FROM debts WHERE user_id = ${user}`;
        await sql`DELETE FROM wallets WHERE user_id = ${user}`;
      }
    });

    it('counts what the user owes as a liability', async () => {
      const user = `${USER}_iou2`;
      try {
        await DebtModel.create(user, 'Kamal', 3_000, 'LKR', 'i_owe');
        const nw = await WalletModel.netWorth(user, 'LKR');
        expect(nw.liabilities).toBe(3_000);
        expect(nw.byType.find((t) => t.type === 'iou_payable')?.total).toBe(3_000);
      } finally {
        await sql`DELETE FROM debts WHERE user_id = ${user}`;
      }
    });
  });

  describe('goal contributions (clamp-aware)', () => {
    it('logs the applied delta, not the requested amount (UPDATE...FROM shape)', async () => {
      const goal = await GoalModel.create(USER, name('Trip'), 1_000, 'LKR');

      // 300 of room used, then a 900 request into 700 of room.
      const first = await GoalModel.addContribution(USER, Number(goal.id), 300, 'manual');
      expect(first!.applied_delta).toBe(300);

      const second = await GoalModel.addContribution(USER, Number(goal.id), 900, 'manual');
      expect(second!.applied_delta).toBe(700); // clamped to the target
      expect(Number(second!.current_amount)).toBe(1_000);
      expect(second!.is_completed).toBe(true);

      // The timeline recorded what actually happened, and nothing extra.
      const logged = await sql`
        SELECT amount FROM goal_contributions WHERE goal_id = ${Number(goal.id)} ORDER BY id ASC
      `;
      expect(logged.map((r: any) => Number(r.amount))).toEqual([300, 700]);
    });

    it('logs nothing when a contribution is fully clamped away', async () => {
      const goal = await GoalModel.create(USER, name('Full'), 500, 'LKR');
      await GoalModel.addContribution(USER, Number(goal.id), 500, 'manual');

      const extra = await GoalModel.addContribution(USER, Number(goal.id), 100, 'manual');
      expect(extra!.applied_delta).toBe(0);

      const logged = await sql`
        SELECT COUNT(*)::int AS n FROM goal_contributions WHERE goal_id = ${Number(goal.id)}
      `;
      expect((logged[0] as any).n).toBe(1);
    });
  });

  describe('recurring repayment rules (clamp / stop / skip)', () => {
    let RecurringModel: (typeof import('./RecurringModel'))['RecurringModel'];
    let materializeTransfer: (typeof import('../services/recurringScheduler'))['materializeTransfer'];

    beforeAll(async () => {
      ({ RecurringModel } = await import('./RecurringModel'));
      ({ materializeTransfer } = await import('../services/recurringScheduler'));
    });

    /**
     * The scheduler looks up `users.currency` with `WHERE id = <userId>`, and
     * users.id is an INTEGER — so the usual string test ids would fail the
     * cast. A large numeric string works: it parses, matches no real user
     * (SERIAL ids are tiny), and the currency lookup falls back to LKR.
     */
    function numericUser(): string {
      return String(2_000_000_000 + Math.floor(Math.random() * 100_000_000));
    }

    async function cleanup(user: string) {
      await sql`DELETE FROM transactions WHERE user_id = ${user}`;
      await sql`DELETE FROM recurring_transactions WHERE user_id = ${user}`;
      await sql`DELETE FROM notifications WHERE user_id = ${user}`;
      await sql`DELETE FROM wallets WHERE user_id = ${user}`;
    }

    it('clamps the final EMI to the outstanding amount and retires the loan rule', async () => {
      const user = numericUser();
      try {
        const bank = await WalletModel.createWithOpening(user, 'Bank', 'bank', 'LKR', 10_000);
        const loan = await WalletModel.createWithOpening(user, 'Loan', 'loan', 'LKR', 300);
        const rule = await RecurringModel.create(
          user, 'Car EMI', 500, 'Transfer', 'monthly', '2026-01-01', 'LKR',
          Number(bank.id), Number(loan.id),
        );

        await materializeTransfer({ ...rule, user_id: user });

        // Owed was 300, EMI 500 → exactly 300 moved; the loan lands at 0, the
        // bank keeps the 200 the rule would have overpaid.
        const balances = await WalletModel.balances(user, 'LKR');
        const loanB = balances.find((b) => b.name === 'Loan')!;
        const bankB = balances.find((b) => b.name === 'Bank')!;
        expect(loanB.balance).toBe(0);
        expect(bankB.balance).toBe(9_700);

        // A finished loan's repayment rule has nothing left to do.
        const after = await RecurringModel.findById(user, Number(rule.id));
        expect(after!.is_active).toBe(false);
      } finally {
        await cleanup(user);
      }
    });

    it('does not touch an already-clear loan, and retires the rule', async () => {
      const user = numericUser();
      try {
        const bank = await WalletModel.createWithOpening(user, 'Bank', 'bank', 'LKR', 10_000);
        const loan = await WalletModel.createWithOpening(user, 'Loan', 'loan', 'LKR', 0);
        const rule = await RecurringModel.create(
          user, 'Car EMI', 500, 'Transfer', 'monthly', '2026-01-01', 'LKR',
          Number(bank.id), Number(loan.id),
        );

        await materializeTransfer({ ...rule, user_id: user });

        // No money moved — the old behavior overpaid a dead loan every run.
        const balances = await WalletModel.balances(user, 'LKR');
        expect(balances.find((b) => b.name === 'Bank')!.balance).toBe(10_000);
        expect(balances.find((b) => b.name === 'Loan')!.balance).toBe(0);
        expect((await RecurringModel.findById(user, Number(rule.id)))!.is_active).toBe(false);
      } finally {
        await cleanup(user);
      }
    });

    it('skips a clear CARD this cycle but keeps the rule alive', async () => {
      const user = numericUser();
      try {
        const bank = await WalletModel.createWithOpening(user, 'Bank', 'bank', 'LKR', 10_000);
        const card = await WalletModel.createWithOpening(user, 'Card', 'credit', 'LKR', 0);
        const rule = await RecurringModel.create(
          user, 'Card autopay', 500, 'Transfer', 'monthly', '2026-01-01', 'LKR',
          Number(bank.id), Number(card.id),
        );

        await materializeTransfer({ ...rule, user_id: user });

        const balances = await WalletModel.balances(user, 'LKR');
        expect(balances.find((b) => b.name === 'Bank')!.balance).toBe(10_000);
        const after = await RecurringModel.findById(user, Number(rule.id));
        // A card owes again next month — the rule must survive the quiet cycle.
        expect(after!.is_active).toBe(true);
        // But this cycle is consumed, so it doesn't refire tomorrow.
        expect(String(after!.next_run)).not.toBe(String(rule.next_run));
      } finally {
        await cleanup(user);
      }
    });
  });

  describe('guards', () => {
    it('knows whether a wallet has any live transactions', async () => {
      const seeded = await WalletModel.createWithOpening(USER, name('Seeded'), 'bank', 'LKR', 100);
      const empty = await WalletModel.createWithOpening(USER, name('Empty'), 'bank', 'LKR', 0);

      expect(await WalletModel.hasTransactions(USER, Number(seeded.id))).toBe(true);
      expect(await WalletModel.hasTransactions(USER, Number(empty.id))).toBe(false);
    });

    it('frees the name again once a wallet is deleted', async () => {
      const n = name('Reused');
      const first = await WalletModel.createWithOpening(USER, n, 'cash', 'LKR', 0);
      await WalletModel.delete(USER, Number(first.id));
      // The old UNIQUE(user_id, name) ignored soft deletes and 409'd here.
      const second = await WalletModel.createWithOpening(USER, n, 'cash', 'LKR', 0);
      expect(Number(second.id)).not.toBe(Number(first.id));
    });
  });
});
