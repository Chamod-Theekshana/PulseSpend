import crypto from 'crypto';
import { sql } from '../config/db';
import { convert } from '../services/exchangeRateService';
import {
  computeBalances,
  deriveGroupSplit,
  type GroupSplitMode,
  type GroupSplitParticipant,
} from '../utils/financeMath';

export interface Group {
  id: number;
  name: string;
  owner_id: string;
  invite_code: string;
  created_at: Date;
}

export interface GroupWithMeta extends Group {
  member_count: number;
  role: string;
}

export interface GroupMember {
  user_id: string;
  name: string | null;
  email: string;
  role: string;
  joined_at: Date;
}

export interface GroupSummary {
  income: number;
  expense: number;
  balance: number;
  currency: string;
  transactionCount: number;
}

export class GroupModel {
  private static generateInviteCode(): string {
    // 8 uppercase base32-ish chars — easy to read out loud, unlikely to collide.
    return crypto.randomBytes(6).toString('base64').replace(/[^A-Z0-9]/gi, '').slice(0, 8).toUpperCase();
  }

  static async create(name: string, ownerId: string): Promise<Group> {
    // Retry a couple of times in the astronomically unlikely event of a code clash.
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = this.generateInviteCode();
      try {
        const rows = await sql`
          INSERT INTO groups (name, owner_id, invite_code)
          VALUES (${name}, ${ownerId}, ${code})
          RETURNING *
        `;
        const group = rows[0] as Group;
        await this.addMember(group.id, ownerId, 'owner');
        return group;
      } catch (err: any) {
        const msg = String(err?.message ?? '');
        if (/invite_code/.test(msg) || /duplicate key/i.test(msg)) continue;
        throw err;
      }
    }
    throw new Error('Could not generate a unique invite code');
  }

  static async findById(id: string | number): Promise<Group | null> {
    const rows = await sql`SELECT * FROM groups WHERE id = ${id}`;
    return (rows[0] as Group) || null;
  }

  static async findByInviteCode(code: string): Promise<Group | null> {
    const rows = await sql`SELECT * FROM groups WHERE invite_code = ${code.trim().toUpperCase()}`;
    return (rows[0] as Group) || null;
  }

  static async isMember(groupId: string | number, userId: string): Promise<boolean> {
    const rows = await sql`
      SELECT 1 FROM group_members WHERE group_id = ${groupId} AND user_id = ${userId}
    `;
    return rows.length > 0;
  }

  static async addMember(groupId: number, userId: string, role = 'member'): Promise<void> {
    await sql`
      INSERT INTO group_members (group_id, user_id, role)
      VALUES (${groupId}, ${userId}, ${role})
      ON CONFLICT (group_id, user_id) DO NOTHING
    `;
  }

  static async removeMember(groupId: string | number, userId: string): Promise<void> {
    await sql`DELETE FROM group_members WHERE group_id = ${groupId} AND user_id = ${userId}`;
  }

  /** Groups the user belongs to, with the member count and the user's role. */
  static async listByUser(userId: string): Promise<GroupWithMeta[]> {
    const rows = await sql`
      SELECT g.*, gm.role AS role,
             (SELECT COUNT(*)::int FROM group_members m WHERE m.group_id = g.id) AS member_count
      FROM groups g
      JOIN group_members gm ON gm.group_id = g.id
      WHERE gm.user_id = ${userId}
      ORDER BY g.created_at DESC
    `;
    return rows as GroupWithMeta[];
  }

  static async listMembers(groupId: string | number): Promise<GroupMember[]> {
    const rows = await sql`
      SELECT gm.user_id, gm.role, gm.joined_at, u.name, u.email
      FROM group_members gm
      JOIN users u ON u.id::text = gm.user_id
      WHERE gm.group_id = ${groupId}
      ORDER BY gm.joined_at ASC
    `;
    return rows as GroupMember[];
  }

  static async memberIds(groupId: string | number): Promise<string[]> {
    const rows = await sql`SELECT user_id FROM group_members WHERE group_id = ${groupId}`;
    return rows.map((r: any) => String(r.user_id));
  }

  /**
   * Read-only feed of the expenses SHARED with this group (most recent first).
   *
   * Scoped by `t.group_id` — NOT by "owner is a member". The membership-only
   * join leaked every member's entire personal ledger into the group: sharing
   * an expense stamps `group_id` (transactionsController), so anything without
   * it is private and must never appear here. This matches memberBalances,
   * which already filters `group_id`, so the feed and the balances reconcile.
   */
  static async aggregatedTransactions(
    groupId: string | number,
    viewerId: string,
    limit = 100,
  ): Promise<any[]> {
    const rows = await sql`
      SELECT t.id, t.user_id, t.title, t.amount, t.currency, t.category, t.created_at,
             t.notes, t.receipt_url,
             COALESCE(u.name, split_part(u.email, '@', 1)) AS member_name,
             (SELECT s.owed_amount FROM group_expense_splits s
              WHERE s.transaction_id = t.id AND s.user_id = ${viewerId}) AS viewer_owed
      FROM transactions t
      LEFT JOIN users u ON u.id::text = t.user_id
      WHERE t.group_id = ${groupId} AND t.deleted_at IS NULL AND t.transfer_id IS NULL
      ORDER BY t.created_at DESC, t.id DESC
      LIMIT ${limit}
    `;
    return rows as any[];
  }

  /**
   * Income/expense/balance over the group's SHARED expenses, in
   * [preferredCurrency]. Same `group_id` scope as the feed — anything a member
   * didn't explicitly share stays private (see aggregatedTransactions).
   */
  static async summary(groupId: string | number, preferredCurrency: string): Promise<GroupSummary> {
    // transfer_id IS NULL keeps settle-up / transfer legs out of the totals — a
    // settle-up's positive payee leg would otherwise be classified as income.
    // Shared income (positive, non-transfer) legitimately counts toward income.
    const rows = await sql`
      SELECT t.amount, t.currency
      FROM transactions t
      WHERE t.group_id = ${groupId} AND t.deleted_at IS NULL AND t.transfer_id IS NULL
    `;
    let income = 0;
    let expense = 0;
    for (const r of rows) {
      const amt = Number((r as any).amount);
      const cur = ((r as any).currency as string) || 'LKR';
      let converted = amt;
      try {
        converted = await convert(amt, cur, preferredCurrency);
      } catch {
        converted = amt;
      }
      if (converted >= 0) income += converted;
      else expense += Math.abs(converted);
    }
    return {
      income,
      expense,
      balance: income - expense,
      currency: preferredCurrency,
      transactionCount: rows.length,
    };
  }

  /** Removes a user's memberships and any groups they own (cascades members). */
  static async purgeUser(userId: string): Promise<void> {
    await sql`DELETE FROM group_members WHERE user_id = ${userId}`;
    await sql`DELETE FROM groups WHERE owner_id = ${userId}`;
  }

  // ── Splitwise-lite balances ────────────────────────────────────────────────

  /**
   * Per-member balances over the group's SHARED transactions (expenses AND
   * income), from frozen per-expense split rows, adjusted by settlements.
   * net > 0 → the member gets money back; net < 0 → they owe. Also returns a
   * greedy minimal-transfer suggestion list ("A pays B X").
   *
   * Income is the mirror of an expense: whoever RECEIVED shared income owes the
   * others their share. Both fold into the same `net = paid − owed` math by
   * feeding income's legs negated — the payment as `−amount` (an expense's −900
   * becomes +900 fronted; an income's +900 becomes −900 "anti-fronted") and each
   * income split share as a negative owed (a receivable, not a debt).
   */
  static async memberBalances(groupId: string | number, preferredCurrency: string) {
    const members = await this.listMembers(groupId);

    // Every shared row a member logged — expense (fronted) or income (received).
    // transfer_id IS NULL drops settle-up / transfer legs: a settle-up is not
    // shared activity and must never be counted here (also see summary()).
    const shared = await sql`
      SELECT user_id, amount, currency
      FROM transactions
      WHERE group_id = ${groupId} AND deleted_at IS NULL AND transfer_id IS NULL AND amount <> 0
    `;
    // Frozen per-expense split rows, joined to the parent so a soft-deleted or
    // transfer row drops its shares. parent_amount carries the sign so income
    // shares can be flipped to receivables below.
    const owedRows = await sql`
      SELECT s.user_id, s.owed_amount, s.currency, t.amount AS parent_amount
      FROM group_expense_splits s
      JOIN transactions t ON t.id = s.transaction_id
      WHERE s.group_id = ${groupId} AND t.deleted_at IS NULL AND t.transfer_id IS NULL
    `;
    // Only confirmed settlements move the balances — a pending/disputed one is
    // recorded but doesn't yet count against what's owed.
    const settlements = await sql`
      SELECT from_user, to_user, amount, currency
      FROM group_settlements
      WHERE group_id = ${groupId} AND status = 'confirmed'
    `;

    if (members.length === 0 && shared.length === 0 && owedRows.length === 0) {
      return { members: [], suggestions: [], total: 0, currency: preferredCurrency };
    }

    // Currency conversion stays in this async wrapper; the balance math itself
    // is the pure, unit-tested computeBalances().
    const toPreferred = async (amount: number, currency: string): Promise<number> => {
      try {
        return await convert(amount, currency || 'LKR', preferredCurrency);
      } catch {
        return amount;
      }
    };

    const payments = [];
    for (const r of shared) {
      // −amount: expense (−900) → +900 fronted; income (+900) → −900, so
      // net = paid − owed puts the income's receiver in debt to the others.
      payments.push({
        user_id: String((r as any).user_id),
        amount: await toPreferred(-Number((r as any).amount), (r as any).currency),
      });
    }

    const owed = [];
    for (const r of owedRows) {
      // Income splits are receivables, not debts → negate the share so it lands
      // on the opposite side of the ledger from an expense share.
      const sign = Number((r as any).parent_amount) < 0 ? 1 : -1;
      owed.push({
        user_id: String((r as any).user_id),
        owed: sign * (await toPreferred(Number((r as any).owed_amount), (r as any).currency)),
      });
    }

    const converted = [];
    for (const s of settlements) {
      converted.push({
        from: String((s as any).from_user),
        to: String((s as any).to_user),
        amount: await toPreferred(Number((s as any).amount), (s as any).currency),
      });
    }

    // Members ∪ anyone who paid/owes — so an ex-member with an outstanding
    // share stays on the books. Names for ex-members fall back to a lookup.
    const nameById = new Map(members.map((m) => [String(m.user_id), m.name || m.email.split('@')[0]]));
    const unknownIds = [
      ...new Set([...payments, ...owed].map((r) => r.user_id).filter((id) => !nameById.has(id))),
    ];
    if (unknownIds.length > 0) {
      const rows = await sql`
        SELECT id::text AS id, COALESCE(name, split_part(email, '@', 1)) AS name
        FROM users WHERE id::text = ANY(${unknownIds})
      `;
      for (const r of rows) nameById.set(String((r as any).id), (r as any).name);
    }
    const memberList = [...nameById.entries()].map(([user_id, name]) => ({ user_id, name }));

    const balances = computeBalances(memberList, payments, owed, converted);
    // Override total with GROSS shared volume (|expense| + |income|): an
    // income-only group must still read as active (the mobile empty-state gate
    // keys off total), whereas computeBalances.total nets income against expense.
    const gross = payments.reduce((a, p) => a + Math.abs(p.amount), 0);
    return { ...balances, total: Math.round(gross * 100) / 100, currency: preferredCurrency };
  }

  static async createSettlement(
    groupId: string | number,
    fromUser: string,
    toUser: string,
    amount: number,
    currency: string,
    transferId: string | null = null,
    status: 'pending' | 'confirmed' = 'confirmed',
  ): Promise<{ id: number }> {
    const rows = await sql`
      INSERT INTO group_settlements (group_id, from_user, to_user, amount, currency, status, transfer_id)
      VALUES (${groupId}, ${fromUser}, ${toUser}, ${amount}, ${currency}, ${status}, ${transferId})
      RETURNING id
    `;
    return { id: Number((rows[0] as any).id) };
  }

  /**
   * Deletes a settlement — either party may undo their own. Returns the removed
   * row (incl. transfer_id) so the caller can reverse its two cash legs, or null
   * if it doesn't exist or the actor isn't the payer or payee.
   */
  static async deleteSettlement(
    groupId: string | number,
    settlementId: number,
    actorUserId: string,
  ): Promise<{ from_user: string; to_user: string; amount: number; currency: string; transfer_id: string | null } | null> {
    const rows = await sql`
      DELETE FROM group_settlements
      WHERE id = ${settlementId} AND group_id = ${groupId}
        AND (from_user = ${actorUserId} OR to_user = ${actorUserId})
      RETURNING from_user, to_user, amount, currency, transfer_id
    `;
    return (rows[0] as any) || null;
  }

  /**
   * The user's net position across every group they belong to, in
   * [preferredCurrency]: a net creditor is owed by the group (receivable/asset),
   * a net debtor owes it (payable/liability). Reuses memberBalances so frozen
   * splits + confirmed settlements are honoured exactly as on the group screen —
   * this is what netWorth adds so group expenses reach assets/liabilities.
   */
  static async userGroupNet(
    userId: string,
    preferredCurrency: string,
  ): Promise<{ receivable: number; payable: number }> {
    const groups = await this.listByUser(userId);
    let receivable = 0;
    let payable = 0;
    for (const g of groups) {
      const bal = await this.memberBalances(g.id, preferredCurrency);
      const mine = bal.members.find((m) => String(m.user_id) === String(userId));
      if (!mine) continue;
      if (mine.net > 0.005) receivable += mine.net;
      else if (mine.net < -0.005) payable += -mine.net;
    }
    return { receivable: Math.round(receivable * 100) / 100, payable: Math.round(payable * 100) / 100 };
  }

  /** Settlement history for a group, newest first, with both members' names. */
  static async listSettlements(groupId: string | number): Promise<any[]> {
    const rows = await sql`
      SELECT s.id, s.from_user, s.to_user, s.amount, s.currency, s.status, s.created_at,
             COALESCE(fu.name, split_part(fu.email, '@', 1)) AS from_name,
             COALESCE(tu.name, split_part(tu.email, '@', 1)) AS to_name
      FROM group_settlements s
      LEFT JOIN users fu ON fu.id::text = s.from_user
      LEFT JOIN users tu ON tu.id::text = s.to_user
      WHERE s.group_id = ${groupId}
      ORDER BY s.created_at DESC, s.id DESC
    `;
    return rows as any[];
  }

  /** Renames a group (owner-checked by the caller). */
  static async rename(groupId: string | number, name: string): Promise<void> {
    await sql`UPDATE groups SET name = ${name} WHERE id = ${groupId}`;
  }

  /** Transfers ownership: promotes [newOwnerId], demotes the old owner to member. */
  static async transferOwnership(groupId: string | number, oldOwnerId: string, newOwnerId: string): Promise<void> {
    await sql.transaction((txn: any) => [
      txn`UPDATE groups SET owner_id = ${newOwnerId} WHERE id = ${groupId}`,
      txn`UPDATE group_members SET role = 'owner' WHERE group_id = ${groupId} AND user_id = ${newOwnerId}`,
      txn`UPDATE group_members SET role = 'member' WHERE group_id = ${groupId} AND user_id = ${oldOwnerId}`,
    ]);
  }

  /**
   * Shares an expense OR income with a group: stamps `group_id` and (re)writes
   * its frozen per-participant split rows, atomically. [totalAbs] is the absolute
   * amount (sign lives on the transaction; income inverts who-owes-whom in
   * memberBalances). [participants] with no split spec defaults to an equal split
   * across all current members. All participants must be current members. The
   * owed rows are frozen in [currency] — later membership changes never re-split
   * this transaction.
   *
   * Returns an error string (→ 400) on an invalid split rather than throwing,
   * so the caller can surface it cleanly.
   */
  static async applyExpenseSplit(
    payerId: string,
    transactionId: number,
    groupId: number,
    totalAbs: number,
    currency: string,
    mode: GroupSplitMode | undefined,
    participants: GroupSplitParticipant[] | undefined,
  ): Promise<{ ok: true } | { ok: false; error: string }> {
    const memberIds = await this.memberIds(groupId);
    const memberSet = new Set(memberIds.map(String));

    // No explicit split → equal across everyone currently in the group.
    let effMode: GroupSplitMode = mode ?? 'equal';
    let effParticipants: GroupSplitParticipant[] = participants ?? [];
    if (effParticipants.length === 0) {
      effMode = 'equal';
      effParticipants = memberIds.map((id) => ({ user_id: String(id) }));
    }
    if (effParticipants.length === 0) {
      return { ok: false, error: 'The group has no members to split between' };
    }
    for (const p of effParticipants) {
      if (!memberSet.has(String(p.user_id))) {
        return { ok: false, error: 'Everyone in the split must be a member of the group' };
      }
    }

    let rows: Array<{ user_id: string; owed: number }>;
    try {
      rows = deriveGroupSplit(effMode, effParticipants, totalAbs, payerId);
    } catch (e: any) {
      return { ok: false, error: String(e?.message || 'Invalid split') };
    }

    const ids = rows.map((r) => r.user_id);
    const owed = rows.map((r) => r.owed);
    // ::text[]/::numeric[] casts: UNNEST params arrive untyped over the driver.
    await sql.transaction((txn: any) => [
      txn`UPDATE transactions SET group_id = ${groupId} WHERE id = ${transactionId} AND user_id = ${payerId}`,
      txn`DELETE FROM group_expense_splits WHERE transaction_id = ${transactionId}`,
      txn`INSERT INTO group_expense_splits (transaction_id, group_id, user_id, owed_amount, currency)
          SELECT ${transactionId}::int, ${groupId}::int, u.user_id, u.owed::numeric, ${currency}
          FROM UNNEST(${ids}::text[], ${owed}::numeric[]) AS u(user_id, owed)`,
    ]);
    return { ok: true };
  }

  /** Clears a transaction's group sharing: unsets group_id and drops splits. */
  static async clearExpenseSplit(payerId: string, transactionId: number): Promise<void> {
    await sql.transaction((txn: any) => [
      txn`DELETE FROM group_expense_splits WHERE transaction_id = ${transactionId}`,
      txn`UPDATE transactions SET group_id = NULL WHERE id = ${transactionId} AND user_id = ${payerId}`,
    ]);
  }
}
