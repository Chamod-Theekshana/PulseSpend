import 'dotenv/config';
import crypto from 'crypto';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

/**
 * The shared-group ledger now reaches personal net worth, executed against a
 * real database.
 *
 * Before this, a group was a parallel ledger disconnected from the four
 * headline figures: a member who fronted a shared expense had their net worth
 * drop by the FULL amount (not just their share), a member who owed a share saw
 * no change at all, and a settle-up moved no real cash. Now:
 *   - a net-creditor's share owed by others is a receivable (asset),
 *   - a net-debtor's share is a payable (liability),
 *   - a settle-up moves cash as a transfer-tagged pair and is net-worth-neutral.
 *
 * This exercises the exact model calls settleUp makes (createSettlement +
 * recordGroupSettleMovement ×2), so the accounting invariant is verified without
 * an HTTP layer. Skips cleanly without a DATABASE_URL; isolated by random ids.
 */
const hasDb = !!process.env.DATABASE_URL;

describe.skipIf(!hasDb)('Group settle → net worth (real database)', () => {
  let sql: (typeof import('../config/db'))['sql'];
  let GroupModel: (typeof import('./GroupModel'))['GroupModel'];
  let WalletModel: (typeof import('./WalletModel'))['WalletModel'];

  // High but within signed-int range; must not collide with real SERIAL ids.
  const A = String(2_010_000_000 + Math.floor(Math.random() * 60_000_000));
  const B = String(2_075_000_001 + Math.floor(Math.random() * 60_000_000));
  const CUR = 'USD';
  let groupId: number;

  const round = (n: number) => Math.round(n * 100) / 100;

  beforeAll(async () => {
    ({ sql } = await import('../config/db'));
    ({ GroupModel } = await import('./GroupModel'));
    ({ WalletModel } = await import('./WalletModel'));

    const seedUser = (id: string) => sql`
      INSERT INTO users (id, email, password, name, currency)
      OVERRIDING SYSTEM VALUE
      VALUES (${Number(id)}, ${'gs_' + id + '@test.local'}, 'x', ${'User ' + id}, ${CUR})
      ON CONFLICT (id) DO NOTHING
    `;
    await seedUser(A);
    await seedUser(B);

    const group = await GroupModel.create('Settle Test', A);
    groupId = Number(group.id);
    await GroupModel.addMember(groupId, A, 'owner');
    await GroupModel.addMember(groupId, B, 'member');

    // A fronts a 1000 shared dinner from the default bucket (wallet_id NULL),
    // split equally → A owes 500, B owes 500. A is the net creditor of 500.
    const rows = await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency, group_id)
      VALUES (${A}, 'Shared dinner', -1000, 'Food', ${CUR}, ${groupId})
      RETURNING id
    `;
    const dinnerId = Number((rows[0] as any).id);
    await sql`
      INSERT INTO group_expense_splits (transaction_id, group_id, user_id, owed_amount, currency)
      VALUES (${dinnerId}, ${groupId}, ${A}, 500, ${CUR}), (${dinnerId}, ${groupId}, ${B}, 500, ${CUR})
    `;
  });

  afterAll(async () => {
    if (!sql) return;
    await sql`DELETE FROM group_settlements WHERE group_id = ${groupId}`;
    await sql`DELETE FROM group_expense_splits WHERE group_id = ${groupId}`;
    await sql`DELETE FROM transactions WHERE user_id IN (${A}, ${B})`;
    await sql`DELETE FROM group_members WHERE group_id = ${groupId}`;
    await sql`DELETE FROM groups WHERE id = ${groupId}`;
    await sql`DELETE FROM users WHERE id IN (${Number(A)}, ${Number(B)})`;
  });

  it('a fronted shared expense makes the payer a receivable and the ower a payable', async () => {
    const aNet = await GroupModel.userGroupNet(A, CUR);
    const bNet = await GroupModel.userGroupNet(B, CUR);
    expect(aNet).toEqual({ receivable: 500, payable: 0 });
    expect(bNet).toEqual({ receivable: 0, payable: 500 });

    // Net worth: A dropped by only their 500 share (wallet −1000 + receivable
    // +500), NOT the full 1000. B dropped by their 500 share (payable) despite
    // paying nothing yet. Before the fix A was −1000 and B was 0.
    const aWorth = await WalletModel.netWorth(A, CUR);
    const bWorth = await WalletModel.netWorth(B, CUR);
    expect(round(aWorth.netWorth)).toBe(-500);
    expect(round(bWorth.netWorth)).toBe(-500);
    // Money on hand tracks real cash: A actually paid 1000, B paid nothing.
    expect(round(await WalletModel.moneyOnHand(A, CUR))).toBe(-1000);
    expect(round(await WalletModel.moneyOnHand(B, CUR))).toBe(0);
  });

  it('settling up moves real cash and is net-worth-neutral for both sides', async () => {
    // Exactly what settleUp does: B pays A 500 — a confirmed settlement plus the
    // two transfer-tagged cash legs (payer out of default bucket, payee in).
    const transferId = crypto.randomUUID();
    const { id } = await GroupModel.createSettlement(groupId, B, A, 500, CUR, transferId);
    await WalletModel.recordGroupSettleMovement(B, null, -500, CUR, 'Settle up: paid A', transferId);
    await WalletModel.recordGroupSettleMovement(A, null, 500, CUR, 'Settle up: B paid you', transferId);

    try {
      // Group positions cleared.
      expect(await GroupModel.userGroupNet(A, CUR)).toEqual({ receivable: 0, payable: 0 });
      expect(await GroupModel.userGroupNet(B, CUR)).toEqual({ receivable: 0, payable: 0 });

      // Net worth UNCHANGED (−500 each): the wallet moved one way while the group
      // position moved the other. Cash, however, actually changed hands.
      expect(round((await WalletModel.netWorth(A, CUR)).netWorth)).toBe(-500);
      expect(round((await WalletModel.netWorth(B, CUR)).netWorth)).toBe(-500);
      expect(round(await WalletModel.moneyOnHand(A, CUR))).toBe(-500); // −1000 + 500 received
      expect(round(await WalletModel.moneyOnHand(B, CUR))).toBe(-500); // 0 − 500 paid

      // The settle-up is invisible to earnings/spendings — both legs are
      // transfer-tagged, like an IOU repayment.
      const legs = await sql`
        SELECT COUNT(*)::int AS n FROM transactions
        WHERE transfer_id = ${transferId} AND transfer_id IS NOT NULL
      `;
      expect(Number((legs[0] as any).n)).toBe(2);
    } finally {
      // leave the settlement in place for the undo test to consume
      void id;
    }
  });

  it('undoing a settle-up reverses both cash legs and restores the positions', async () => {
    const listed = await GroupModel.listSettlements(groupId);
    expect(listed.length).toBe(1);
    const sid = Number(listed[0].id);

    // Either party may undo; B (the payer) does. Mirror the controller: delete
    // the row, then reverse the two legs by their shared transfer_id.
    const removed = await GroupModel.deleteSettlement(groupId, sid, B);
    expect(removed).not.toBeNull();
    expect(removed!.transfer_id).toBeTruthy();
    await WalletModel.deleteByTransferId([A, B], removed!.transfer_id!);

    // Back to the pre-settle state: positions and cash both restored.
    expect(await GroupModel.userGroupNet(A, CUR)).toEqual({ receivable: 500, payable: 0 });
    expect(await GroupModel.userGroupNet(B, CUR)).toEqual({ receivable: 0, payable: 500 });
    expect(round(await WalletModel.moneyOnHand(A, CUR))).toBe(-1000);
    expect(round(await WalletModel.moneyOnHand(B, CUR))).toBe(0);
    // The legs are gone.
    const legs = await sql`
      SELECT COUNT(*)::int AS n FROM transactions WHERE transfer_id = ${removed!.transfer_id}
    `;
    expect(Number((legs[0] as any).n)).toBe(0);
  });
});
