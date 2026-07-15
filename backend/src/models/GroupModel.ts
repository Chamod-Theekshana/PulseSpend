import crypto from 'crypto';
import { sql } from '../config/db';
import { convert } from '../services/exchangeRateService';
import { computeBalances } from '../utils/financeMath';

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

  /** Combined, read-only transaction feed for the whole group (most recent first). */
  static async aggregatedTransactions(groupId: string | number, limit = 100): Promise<any[]> {
    const rows = await sql`
      SELECT t.id, t.user_id, t.title, t.amount, t.currency, t.category, t.created_at,
             COALESCE(u.name, split_part(u.email, '@', 1)) AS member_name
      FROM transactions t
      JOIN group_members gm ON gm.user_id = t.user_id AND gm.group_id = ${groupId}
      LEFT JOIN users u ON u.id::text = t.user_id
      WHERE t.deleted_at IS NULL
      ORDER BY t.created_at DESC, t.id DESC
      LIMIT ${limit}
    `;
    return rows as any[];
  }

  /** Merged income/expense/balance across all members, in [preferredCurrency]. */
  static async summary(groupId: string | number, preferredCurrency: string): Promise<GroupSummary> {
    const rows = await sql`
      SELECT t.amount, t.currency
      FROM transactions t
      JOIN group_members gm ON gm.user_id = t.user_id AND gm.group_id = ${groupId}
      WHERE t.deleted_at IS NULL
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
   * Per-member balances over the group's SHARED expenses (transactions with
   * group_id set), split equally between members, adjusted by settlements.
   * net > 0 → the member gets money back; net < 0 → they owe. Also returns a
   * greedy minimal-transfer suggestion list ("A pays B X").
   */
  static async memberBalances(groupId: string | number, preferredCurrency: string) {
    const members = await this.listMembers(groupId);
    if (members.length === 0) {
      return { members: [], suggestions: [], total: 0, currency: preferredCurrency };
    }

    const shared = await sql`
      SELECT user_id, amount, currency
      FROM transactions
      WHERE group_id = ${groupId} AND deleted_at IS NULL AND amount < 0
    `;
    const settlements = await sql`
      SELECT from_user, to_user, amount, currency
      FROM group_settlements
      WHERE group_id = ${groupId}
    `;

    // Currency conversion stays in this async wrapper; the balance math itself
    // is the pure, unit-tested computeBalances().
    const toPreferred = async (amount: number, currency: string): Promise<number> => {
      try {
        return await convert(amount, currency || 'LKR', preferredCurrency);
      } catch {
        return amount;
      }
    };

    const expenses = [];
    for (const r of shared) {
      expenses.push({
        user_id: String((r as any).user_id),
        amount: await toPreferred(Math.abs(Number((r as any).amount)), (r as any).currency),
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

    const memberList = members.map((m) => ({
      user_id: String(m.user_id),
      name: m.name || m.email.split('@')[0],
    }));

    const balances = computeBalances(memberList, expenses, converted);
    return { ...balances, currency: preferredCurrency };
  }

  static async createSettlement(
    groupId: string | number,
    fromUser: string,
    toUser: string,
    amount: number,
    currency: string,
  ): Promise<void> {
    await sql`
      INSERT INTO group_settlements (group_id, from_user, to_user, amount, currency)
      VALUES (${groupId}, ${fromUser}, ${toUser}, ${amount}, ${currency})
    `;
  }
}
