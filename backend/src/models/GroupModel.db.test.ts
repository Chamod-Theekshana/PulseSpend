import 'dotenv/config';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

/**
 * Shared-group privacy, executed against a real database.
 *
 * The regression this guards was a live leak: the group feed and summary joined
 * members to their transactions by user_id ALONE, so every member saw every
 * other member's ENTIRE personal ledger — not just the expenses shared to the
 * group. The scoping key (transactions.group_id) already existed and was
 * populated on share; the queries just never read it. A pure test can't catch a
 * missing WHERE clause, so this runs the real SQL.
 *
 * Skips cleanly without a DATABASE_URL. Isolated by two random-id test users.
 */
const hasDb = !!process.env.DATABASE_URL;

describe.skipIf(!hasDb)('GroupModel privacy (real database)', () => {
  let sql: (typeof import('../config/db'))['sql'];
  let GroupModel: (typeof import('./GroupModel'))['GroupModel'];

  // High but within signed-int range (max 2,147,483,647): users.id is INTEGER,
  // and these must not collide with the small SERIAL ids of real users.
  const A = String(2_000_000_000 + Math.floor(Math.random() * 70_000_000));
  const B = String(2_070_000_001 + Math.floor(Math.random() * 70_000_000));
  let groupId: number;

  beforeAll(async () => {
    ({ sql } = await import('../config/db'));
    ({ GroupModel } = await import('./GroupModel'));

    // Real user rows: listMembers (and the balance math) inner-join users, so
    // member names must resolve for the reconciliation check to run.
    const seedUser = (id: string) => sql`
      INSERT INTO users (id, email, password, name)
      OVERRIDING SYSTEM VALUE
      VALUES (${Number(id)}, ${'grp_' + id + '@test.local'}, 'x', ${'User ' + id})
      ON CONFLICT (id) DO NOTHING
    `;
    await seedUser(A);
    await seedUser(B);

    const group = await GroupModel.create('Privacy Test', A);
    groupId = Number(group.id);
    await GroupModel.addMember(groupId, A, 'owner');
    await GroupModel.addMember(groupId, B, 'member');

    // Each member: one PRIVATE expense (group_id NULL) + one SHARED (group_id set).
    const ins = async (user: string, title: string, amount: number, gid: number | null) => {
      const rows = await sql`
        INSERT INTO transactions (user_id, title, amount, category, currency, group_id)
        VALUES (${user}, ${title}, ${amount}, 'Food', 'LKR', ${gid})
        RETURNING id
      `;
      return Number((rows[0] as any).id);
    };
    await ins(A, 'A private lunch', -500, null);
    const dinnerId = await ins(A, 'A shared dinner', -2000, groupId);
    await ins(B, 'B private coffee', -300, null);
    const taxiId = await ins(B, 'B shared taxi', -1000, groupId);

    // Frozen equal splits for the two shared expenses (2 members → half each).
    const split = (txId: number, owed: number) => sql`
      INSERT INTO group_expense_splits (transaction_id, group_id, user_id, owed_amount, currency)
      VALUES (${txId}, ${groupId}, ${A}, ${owed}, 'LKR'), (${txId}, ${groupId}, ${B}, ${owed}, 'LKR')
    `;
    await split(dinnerId, 1000); // 2000 dinner → 1000 each
    await split(taxiId, 500); //    1000 taxi   → 500 each
  });

  afterAll(async () => {
    if (!sql) return;
    await sql`DELETE FROM group_expense_splits WHERE group_id = ${groupId}`;
    await sql`DELETE FROM transactions WHERE user_id IN (${A}, ${B})`;
    await sql`DELETE FROM group_members WHERE group_id = ${groupId}`;
    await sql`DELETE FROM groups WHERE id = ${groupId}`;
    await sql`DELETE FROM users WHERE id IN (${Number(A)}, ${Number(B)})`;
  });

  it('feed returns ONLY shared expenses, never members\' private ones', async () => {
    const feed = await GroupModel.aggregatedTransactions(groupId, A);
    const titles = feed.map((r: any) => r.title).sort();
    expect(titles).toEqual(['A shared dinner', 'B shared taxi']);
    // The leak was precisely these showing up:
    expect(titles).not.toContain('A private lunch');
    expect(titles).not.toContain('B private coffee');
  });

  it('summary counts and totals only the shared expenses', async () => {
    const summary = await GroupModel.summary(groupId, 'LKR');
    expect(summary.transactionCount).toBe(2);
    // 2000 + 1000 shared, not the 800 of private spend.
    expect(summary.expense).toBe(3000);
    expect(summary.income).toBe(0);
  });

  it('balances net out from the frozen splits (A fronted more → A gets back)', async () => {
    const balances = await GroupModel.memberBalances(groupId, 'LKR');
    expect(balances.total).toBe(3000);
    // A paid 2000, owes 1500 (1000+500) → +500. B paid 1000, owes 1500 → −500.
    expect(balances.members.find((m: any) => m.user_id === A)!.net).toBe(500);
    expect(balances.members.find((m: any) => m.user_id === B)!.net).toBe(-500);
  });

  it('adding a member LATER does not re-split past expenses (freeze)', async () => {
    const before = await GroupModel.memberBalances(groupId, 'LKR');
    const beforeNets = before.members.map((m: any) => `${m.user_id}:${m.net}`).sort();

    const C = String(2_140_000_002 + Math.floor(Math.random() * 7_000_000));
    try {
      await sql`
        INSERT INTO users (id, email, password, name) OVERRIDING SYSTEM VALUE
        VALUES (${Number(C)}, ${'grp_' + C + '@test.local'}, 'x', ${'User ' + C})
        ON CONFLICT (id) DO NOTHING
      `;
      await GroupModel.addMember(groupId, C, 'member');

      const after = await GroupModel.memberBalances(groupId, 'LKR');
      const afterNets = after.members.map((m: any) => `${m.user_id}:${m.net}`).sort();
      // The old total/members math would have re-split everything 3 ways and
      // handed C a debt for expenses from before they joined. Frozen splits
      // mean C owes nothing and A/B are byte-identical.
      expect(after.members.find((m: any) => m.user_id === C)!.net).toBe(0);
      expect(afterNets).toEqual([...beforeNets, `${C}:0`].sort());
    } finally {
      await sql`DELETE FROM group_members WHERE group_id = ${groupId} AND user_id = ${C}`;
      await sql`DELETE FROM users WHERE id = ${Number(C)}`;
    }
  });

  it('an ex-member keeps their owed share after leaving', async () => {
    // Remove B from the group; their frozen split rows remain.
    await GroupModel.removeMember(groupId, B);
    try {
      const balances = await GroupModel.memberBalances(groupId, 'LKR');
      const bal = balances.members.find((m: any) => m.user_id === B);
      expect(bal).toBeDefined(); // still on the books
      expect(bal!.net).toBe(-500); // still owes
    } finally {
      await GroupModel.addMember(groupId, B, 'member'); // restore for other tests
    }
  });

  it('applyExpenseSplit freezes an unequal split and rejects non-members', async () => {
    const rows = await sql`
      INSERT INTO transactions (user_id, title, amount, category, currency)
      VALUES (${A}, 'Unequal dinner', -100, 'Food', 'LKR') RETURNING id
    `;
    const txId = Number((rows[0] as any).id);
    try {
      // 70/30 between A and B.
      const ok = await GroupModel.applyExpenseSplit(A, txId, groupId, 100, 'LKR', 'exact', [
        { user_id: A, value: 70 },
        { user_id: B, value: 30 },
      ]);
      expect(ok.ok).toBe(true);
      const written = await sql`
        SELECT user_id, owed_amount FROM group_expense_splits WHERE transaction_id = ${txId} ORDER BY owed_amount DESC
      `;
      expect(written.map((r: any) => Number(r.owed_amount))).toEqual([70, 30]);
      // group_id was stamped atomically.
      const stamped = await sql`SELECT group_id FROM transactions WHERE id = ${txId}`;
      expect(Number((stamped[0] as any).group_id)).toBe(groupId);

      // A stranger can't be a participant.
      const bad = await GroupModel.applyExpenseSplit(A, txId, groupId, 100, 'LKR', 'equal', [
        { user_id: '999999999' },
      ]);
      expect(bad.ok).toBe(false);
    } finally {
      await sql`DELETE FROM group_expense_splits WHERE transaction_id = ${txId}`;
      await sql`DELETE FROM transactions WHERE id = ${txId}`;
    }
  });

  it('a soft-deleted shared expense drops out of balances', async () => {
    await sql`UPDATE transactions SET deleted_at = NOW() WHERE user_id = ${A} AND title = 'A shared dinner'`;
    try {
      const balances = await GroupModel.memberBalances(groupId, 'LKR');
      // Only the 1000 taxi (paid by B, split 500/500) remains → A owes 500, B
      // gets 500 back. The dinner's payment AND its owed rows both drop out.
      expect(balances.total).toBe(1000);
      expect(balances.members.find((m: any) => m.user_id === A)!.net).toBe(-500);
      expect(balances.members.find((m: any) => m.user_id === B)!.net).toBe(500);
    } finally {
      await sql`UPDATE transactions SET deleted_at = NULL WHERE user_id = ${A} AND title = 'A shared dinner'`;
    }
  });
});
