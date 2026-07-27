import 'dotenv/config';
import crypto from 'crypto';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

/**
 * Shared INCOME in a group is the mirror of a shared expense, executed against a
 * real database.
 *
 * Whoever RECEIVES shared income owes the others their share. It folds into the
 * same `net = paid − owed` math by feeding income's legs negated — proven here:
 * a 900 income received by A, split 3 ways, makes A a debtor of 600 and B/C
 * creditors of 300 each. Net worth reflects each member's real share, settling
 * is net-worth-neutral, and a settle-up is NEVER counted as group income
 * (the `transfer_id IS NULL` hardening).
 *
 * Skips cleanly without a DATABASE_URL; isolated by random ids.
 */
const hasDb = !!process.env.DATABASE_URL;

describe.skipIf(!hasDb)('Group income → reverse split (real database)', () => {
  let sql: (typeof import('../config/db'))['sql'];
  let GroupModel: (typeof import('./GroupModel'))['GroupModel'];
  let WalletModel: (typeof import('./WalletModel'))['WalletModel'];

  const A = String(2_020_000_000 + Math.floor(Math.random() * 40_000_000));
  const B = String(2_062_000_001 + Math.floor(Math.random() * 40_000_000));
  const C = String(2_104_000_002 + Math.floor(Math.random() * 40_000_000));
  const CUR = 'USD';
  let groupId: number;

  const round = (n: number) => Math.round(n * 100) / 100;
  const netOf = (bal: any, id: string) => bal.members.find((m: any) => String(m.user_id) === id)!.net;

  beforeAll(async () => {
    ({ sql } = await import('../config/db'));
    ({ GroupModel } = await import('./GroupModel'));
    ({ WalletModel } = await import('./WalletModel'));

    const seedUser = (id: string) => sql`
      INSERT INTO users (id, email, password, name, currency)
      OVERRIDING SYSTEM VALUE
      VALUES (${Number(id)}, ${'gi_' + id + '@test.local'}, 'x', ${'User ' + id}, ${CUR})
      ON CONFLICT (id) DO NOTHING
    `;
    await seedUser(A);
    await seedUser(B);
    await seedUser(C);

    const group = await GroupModel.create('Income Test', A);
    groupId = Number(group.id);
    await GroupModel.addMember(groupId, A, 'owner');
    await GroupModel.addMember(groupId, B, 'member');
    await GroupModel.addMember(groupId, C, 'member');

    // A receives a 900 shared income (into the default bucket), split equally
    // 3 ways via the real write path (applyExpenseSplit stamps group_id + freezes
    // the 300/300/300 shares).
    const rows = await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency)
      VALUES (${A}, 'Shared refund', 900, 'Income', ${CUR})
      RETURNING id
    `;
    const incomeId = Number((rows[0] as any).id);
    const applied = await GroupModel.applyExpenseSplit(
      A, incomeId, groupId, 900, CUR, 'equal',
      [{ user_id: A }, { user_id: B }, { user_id: C }],
    );
    expect(applied.ok).toBe(true);
  });

  afterAll(async () => {
    if (!sql) return;
    await sql`DELETE FROM group_settlements WHERE group_id = ${groupId}`;
    await sql`DELETE FROM group_expense_splits WHERE group_id = ${groupId}`;
    await sql`DELETE FROM transactions WHERE user_id IN (${A}, ${B}, ${C})`;
    await sql`DELETE FROM group_members WHERE group_id = ${groupId}`;
    await sql`DELETE FROM groups WHERE id = ${groupId}`;
    await sql`DELETE FROM users WHERE id IN (${Number(A)}, ${Number(B)}, ${Number(C)})`;
  });

  it('the receiver owes the others their share (reverse of an expense)', async () => {
    const bal = await GroupModel.memberBalances(groupId, CUR);
    // A received 900, owes B and C 300 each → net −600. B and C are owed 300.
    expect(round(netOf(bal, A))).toBe(-600);
    expect(round(netOf(bal, B))).toBe(300);
    expect(round(netOf(bal, C))).toBe(300);
    // Nets sum to ~0 (money is conserved), unlike the half-counted phantom-debt bug.
    expect(round(netOf(bal, A) + netOf(bal, B) + netOf(bal, C))).toBe(0);
    // Gross total is the income volume (not netted to zero).
    expect(round(bal.total)).toBe(900);

    // Group positions: A is the payable, B and C are receivables.
    expect(await GroupModel.userGroupNet(A, CUR)).toEqual({ receivable: 0, payable: 600 });
    expect(await GroupModel.userGroupNet(B, CUR)).toEqual({ receivable: 300, payable: 0 });

    // Net worth: A received 900 cash but owes 600 → +300 (their real share);
    // B and C are each owed 300 → +300. Everyone ends at their 300 share.
    expect(round((await WalletModel.netWorth(A, CUR)).netWorth)).toBe(300);
    expect(round((await WalletModel.netWorth(B, CUR)).netWorth)).toBe(300);
    expect(round(await WalletModel.moneyOnHand(A, CUR))).toBe(900); // real cash received

    // The shared income shows up under group Income.
    const summary = await GroupModel.summary(groupId, CUR);
    expect(round(summary.income)).toBe(900);
    expect(round(summary.expense)).toBe(0);
  });

  it('the receiver settling with the others is net-worth-neutral and not income', async () => {
    // A settles their debt: pays B 300 and C 300 (mirrors settleUp).
    for (const payee of [B, C]) {
      const tid = crypto.randomUUID();
      await GroupModel.createSettlement(groupId, A, payee, 300, CUR, tid);
      await WalletModel.recordGroupSettleMovement(A, null, -300, CUR, `Settle up: paid ${payee}`, tid);
      await WalletModel.recordGroupSettleMovement(payee, null, 300, CUR, `Settle up: A paid you`, tid);
    }

    const bal = await GroupModel.memberBalances(groupId, CUR);
    expect(round(netOf(bal, A))).toBe(0);
    expect(round(netOf(bal, B))).toBe(0);
    expect(round(netOf(bal, C))).toBe(0);

    // Net worth unchanged (+300 each); cash actually moved.
    expect(round((await WalletModel.netWorth(A, CUR)).netWorth)).toBe(300);
    expect(round((await WalletModel.netWorth(B, CUR)).netWorth)).toBe(300);
    expect(round(await WalletModel.moneyOnHand(A, CUR))).toBe(300); // 900 − 300 − 300

    // The settle-up cash must NOT be counted as group income — income stays 900.
    const summary = await GroupModel.summary(groupId, CUR);
    expect(round(summary.income)).toBe(900);
  });

  it('a transfer-tagged row stamped with the group id is excluded from income & balances', async () => {
    // Defensive: even if a transfer leg somehow carried this group_id, the
    // transfer_id IS NULL filter keeps it out of summary income and balances.
    const tid = crypto.randomUUID();
    await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, group_id, transfer_id)
      VALUES (${B}, 'stray transfer', 500, 'Group Settle', ${CUR}, ${groupId}, ${tid})
    `;
    try {
      const summary = await GroupModel.summary(groupId, CUR);
      expect(round(summary.income)).toBe(900); // NOT 1400
      const bal = await GroupModel.memberBalances(groupId, CUR);
      expect(round(bal.total)).toBe(900); // the stray 500 doesn't distort the volume
    } finally {
      await sql`DELETE FROM transactions WHERE transfer_id = ${tid}`;
    }
  });
});
