import crypto from 'crypto';
import { MAX_AMOUNT } from '../utils/financeMath';
import { GroupModel } from '../models/GroupModel';
import { UserModel } from '../models/UserModel';
import { WalletModel } from '../models/WalletModel';
import { sendPushToUser } from '../services/pushService';
import { emitToUser } from '../socket';
import { sql } from '../config/db';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

/**
 * Parses an optional wallet id (where the payer's settle-up cash left from):
 * undefined/null/0 = the default cash bucket, >0 must be the caller's wallet.
 * Mirrors the IOU settle helper so both settle flows behave the same.
 */
async function parseSettleWallet(
  userId: string,
  raw: unknown,
): Promise<{ walletId: number | null; error?: string }> {
  if (raw === undefined || raw === null) return { walletId: null };
  const id = Number(raw);
  if (!Number.isInteger(id) || id < 0) return { walletId: null, error: 'Invalid wallet' };
  if (id > 0 && !(await WalletModel.findById(userId, id))) {
    return { walletId: null, error: 'Wallet not found' };
  }
  return { walletId: id };
}

/** Wakes every member's group screens in real time. */
async function emitGroupChanged(groupId: string | number): Promise<void> {
  try {
    for (const memberId of await GroupModel.memberIds(groupId)) {
      emitToUser(memberId, 'group:changed', { groupId: Number(groupId) });
    }
  } catch (err) {
    console.error('[Groups] emit failed:', err);
  }
}

/** Confirms the caller owns the group; 403 otherwise. Returns the group or null. */
async function requireOwner(groupId: string, userId: string, res: Response): Promise<any | null> {
  const group = await GroupModel.findById(groupId);
  if (!group) {
    res.status(404).json({ message: 'Group not found' });
    return null;
  }
  if (String(group.owner_id) !== userId) {
    res.status(403).json({ message: 'Only the group owner can do that' });
    return null;
  }
  return group;
}

async function preferredCurrency(userId: string): Promise<string> {
  const rows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
  return ((rows[0] as any)?.currency as string) || 'LKR';
}

/** POST /api/groups — create a shared group; the creator becomes its owner. */
export async function createGroup(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
  if (!name) return res.status(400).json({ message: 'Group name is required' });
  if (name.length > 255) return res.status(400).json({ message: 'Group name is too long' });

  const group = await GroupModel.create(name, userId);
  return res.status(201).json({ message: 'Group created', group });
}

/** GET /api/groups — groups the signed-in user belongs to. */
export async function listGroups(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groups = await GroupModel.listByUser(userId);
  return res.status(200).json({ groups });
}

/** POST /api/groups/join — join a group via its invite code. */
export async function joinGroup(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const code = typeof req.body?.invite_code === 'string' ? req.body.invite_code.trim() : '';
  if (!code) return res.status(400).json({ message: 'Invite code is required' });

  const group = await GroupModel.findByInviteCode(code);
  if (!group) return res.status(404).json({ message: 'No group found for that invite code' });

  if (await GroupModel.isMember(group.id, userId)) {
    return res.status(200).json({ message: 'Already a member', group });
  }
  await GroupModel.addMember(group.id, userId, 'member');
  void emitGroupChanged(group.id);

  // Tell existing members someone joined (fire-and-forget; never block the join).
  void (async () => {
    try {
      const joinerName = await UserModel.displayName(userId);
      const memberIds = await GroupModel.memberIds(group.id);
      for (const memberId of memberIds) {
        if (memberId === userId) continue;
        await sendPushToUser(
          memberId,
          `New member in ${group.name}`,
          `${joinerName} just joined the group.`,
          { type: 'group_activity', groupId: String(group.id) },
        );
      }
    } catch (err) {
      console.error('[Groups] join notification failed:', err);
    }
  })();

  return res.status(200).json({ message: 'Joined group', group });
}

/** GET /api/groups/:id/members — member roster (members only). */
export async function getMembers(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const members = await GroupModel.listMembers(groupId);
  return res.status(200).json({ members });
}

/** GET /api/groups/:id/transactions — combined feed + merged summary (members only). */
export async function getGroupTransactions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const currency = await preferredCurrency(userId);
  const [transactions, summary] = await Promise.all([
    GroupModel.aggregatedTransactions(groupId, userId),
    GroupModel.summary(groupId, currency),
  ]);
  return res.status(200).json({ transactions, summary });
}

/** GET /api/groups/:id/export?format=csv — Export combined feed to CSV */
export async function exportGroupTransactions(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const format = req.query.format as string;

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }

  if (format !== 'csv' && format !== 'pdf') {
    return res.status(400).json({ message: 'Unsupported export format. Use ?format=csv or ?format=pdf' });
  }

  const transactions = await GroupModel.aggregatedTransactions(groupId, userId);
  
  if (transactions.length === 0) {
    return res.status(404).json({ message: 'No group transactions to export' });
  }

  if (format === 'pdf') {
    const currency = await preferredCurrency(userId);
    const summary = await GroupModel.summary(groupId, currency);
    const members = await GroupModel.memberSpendingBreakdown(groupId, currency);
    const group = await GroupModel.findById(groupId);
    
    const { convert } = await import('../services/exchangeRateService');
    const pdfTransactions = [];
    for (const t of transactions.slice(0, 50)) { // limit to 50 for the report
      const amt = Number(t.amount);
      const cur = t.currency || 'LKR';
      let converted = amt;
      try { converted = await convert(amt, cur, currency); } catch { }
      pdfTransactions.push({
        date: t.created_at instanceof Date ? t.created_at.toISOString().slice(0, 10) : String(t.created_at).slice(0, 10),
        title: String(t.title),
        memberName: String(t.member_name),
        amount: converted,
        category: String(t.category)
      });
    }

    const data = {
      groupName: group?.name || 'Group',
      currency,
      income: summary.income,
      expense: summary.expense,
      balance: summary.balance,
      members: members.map(m => ({
        name: m.memberName,
        amount: m.total,
        pct: summary.expense > 0 ? (m.total / summary.expense) * 100 : 0
      })).sort((a, b) => b.amount - a.amount),
      transactions: pdfTransactions,
      transactionCount: transactions.length
    };
    
    const { renderGroupReportPdf } = await import('../services/pdfReportService');
    const doc = renderGroupReportPdf(data);
    
    const filename = `group_${groupId}_export_${new Date().toISOString().split('T')[0]}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    doc.pipe(res);
    return;
  }

  // Generate CSV manually (RFC 4180 standard)
  const header = ['Date', 'Title', 'Member', 'Category', 'Amount', 'Currency', 'Notes', 'Receipt URL'];
  const escapeCsv = (val: any) => {
    if (val == null) return '';
    const s = String(val).replace(/"/g, '""');
    if (s.includes(',') || s.includes('"') || s.includes('\n')) return `"${s}"`;
    return s;
  };

  const rows = transactions.map((t) => [
    t.created_at,
    t.title,
    t.member_name,
    t.category,
    t.amount,
    t.currency,
    t.notes || '',
    t.receipt_url || '',
  ]);

  const csvString = [header, ...rows].map((row) => row.map(escapeCsv).join(',')).join('\r\n');

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="group_${groupId}_export_${new Date().toISOString().split('T')[0]}.csv"`);
  // Prepend UTF-8 BOM so Excel opens it correctly.
  return res.send('\uFEFF' + csvString);
}

/** GET /api/groups/:id/transactions/:txId — full details of a single group transaction (members only). */
export async function getGroupTransactionDetail(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const txId = String(req.params.txId);

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }

  const detail = await GroupModel.getTransactionDetail(groupId, txId, userId);
  if (!detail) {
    return res.status(404).json({ message: 'Transaction not found in this group' });
  }

  return res.status(200).json({ detail });
}

/** GET /api/groups/:id/analytics — per-member spending breakdown (members only). */
export async function getGroupAnalytics(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }

  const currency = await preferredCurrency(userId);
  const analytics = await GroupModel.memberSpendingBreakdown(groupId, currency);

  return res.status(200).json({ analytics, currency });
}

/** GET /api/groups/:id/goals — savings goals shared with this group. */
export async function getGroupGoals(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const { GoalModel } = await import('../models/GoalModel');
  const goals = await GoalModel.listByGroup(Number(groupId));
  return res.status(200).json({ goals });
}

/** GET /api/groups/:id/balances — Splitwise-lite member balances + suggestions. */
export async function getGroupBalances(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const balances = await GroupModel.memberBalances(groupId, await preferredCurrency(userId));
  return res.status(200).json(balances);
}

/**
 * POST /api/groups/:id/settle — record "I paid <to_user> <amount>".
 *
 * Immediate and symmetric: the group balance shifts NOW, and the real cash moves
 * as a transfer-tagged pair — the payer's wallet out, the payee's default bucket
 * in — linked by one transfer_id so an undo reverses both. Net worth stays flat
 * for both: the wallet moves one way while the group receivable/payable (counted
 * in netWorth) moves the other. `wallet_id` (optional) is where the payer's cash
 * came from; the payee's lands in their default bucket since we don't know theirs.
 */
export async function settleUp(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const { to_user, amount, currency, wallet_id } = req.body ?? {};

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const toUser = String(to_user ?? '');
  if (!toUser || toUser === userId || !(await GroupModel.isMember(groupId, toUser))) {
    return res.status(400).json({ message: 'to_user must be another member of this group' });
  }
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0 || amt > MAX_AMOUNT) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }
  const cur = typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : 'LKR';
  const rounded = Math.round(amt * 100) / 100;

  const { walletId, error } = await parseSettleWallet(userId, wallet_id);
  if (error) return res.status(404).json({ message: error });

  const [payerName, payeeName] = await Promise.all([
    UserModel.displayName(userId),
    UserModel.displayName(toUser),
  ]);

  // One transfer_id ties the settlement to its two cash legs so an undo is clean.
  const transferId = crypto.randomUUID();
  const { id } = await GroupModel.createSettlement(groupId, userId, toUser, rounded, cur, transferId);
  await WalletModel.recordGroupSettleMovement(userId, walletId, -rounded, cur, `Settle up: paid ${payeeName}`, transferId);
  await WalletModel.recordGroupSettleMovement(toUser, null, rounded, cur, `Settle up: ${payerName} paid you`, transferId);

  void emitGroupChanged(groupId);
  emitToUser(userId, 'wallet:changed', { group_settle: id });
  emitToUser(toUser, 'wallet:changed', { group_settle: id });

  const group = await GroupModel.findById(groupId);
  void (async () => {
    try {
      await sendPushToUser(
        toUser,
        `Payment in ${group?.name ?? 'your group'}`,
        `${payerName} settled ${rounded.toFixed(2)} ${cur} with you.`,
        { type: 'group_activity', groupId: String(groupId) },
      );
    } catch (err) {
      console.error('[Groups] settle notification failed:', err);
    }
  })();

  return res.status(201).json({ message: 'Settled up', settlement_id: id });
}

/** GET /api/groups/:id/settlements — settle-up history (members only). */
export async function getSettlements(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const settlements = await GroupModel.listSettlements(groupId);
  return res.status(200).json({ settlements });
}

/**
 * DELETE /api/groups/:id/settlements/:sid — either party undoes a settle-up.
 * Removes the row and reverses BOTH cash legs (via the shared transfer_id), so
 * the group balance snaps back and each side's wallet/net worth returns to where
 * it was. The counterpart is notified.
 */
export async function deleteSettlement(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const sid = Number(req.params.sid);

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const removed = await GroupModel.deleteSettlement(groupId, sid, userId);
  if (!removed) {
    return res.status(404).json({ message: 'No settlement of yours to undo' });
  }
  const from = String(removed.from_user);
  const to = String(removed.to_user);
  if (removed.transfer_id) {
    await WalletModel.deleteByTransferId([from, to], removed.transfer_id);
  }
  void emitGroupChanged(groupId);
  emitToUser(from, 'wallet:changed', { group_settle_undo: sid });
  emitToUser(to, 'wallet:changed', { group_settle_undo: sid });

  // Tell the other party their settlement was undone (the actor already knows).
  const other = userId === from ? to : from;
  void (async () => {
    try {
      const actor = await UserModel.displayName(userId);
      const group = await GroupModel.findById(groupId);
      await sendPushToUser(
        other,
        `Settle-up undone in ${group?.name ?? 'your group'}`,
        `${actor} undid a ${Number(removed.amount).toFixed(2)} ${removed.currency} settle-up.`,
        { type: 'group_activity', groupId: String(groupId) },
      );
    } catch (err) {
      console.error('[Groups] settle-undo notification failed:', err);
    }
  })();
  return res.json({ message: 'Settlement undone' });
}

/** PUT /api/groups/:id — rename the group (owner only). */
export async function renameGroup(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
  if (!name) return res.status(400).json({ message: 'Group name is required' });
  if (name.length > 255) return res.status(400).json({ message: 'Group name is too long' });
  if (!(await requireOwner(groupId, userId, res))) return;

  await GroupModel.rename(groupId, name);
  void emitGroupChanged(groupId);
  return res.json({ message: 'Group renamed', group: await GroupModel.findById(groupId) });
}

/** PUT /api/groups/:id/owner — hand ownership to another member (owner only). */
export async function transferOwnership(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const newOwner = String(req.body?.user_id ?? '');
  if (!(await requireOwner(groupId, userId, res))) return;
  if (!newOwner || newOwner === userId || !(await GroupModel.isMember(groupId, newOwner))) {
    return res.status(400).json({ message: 'Pick another member to hand ownership to' });
  }
  await GroupModel.transferOwnership(groupId, userId, newOwner);
  void emitGroupChanged(groupId);
  void (async () => {
    try {
      const group = await GroupModel.findById(groupId);
      await sendPushToUser(
        newOwner,
        `You now own ${group?.name ?? 'the group'}`,
        `${await UserModel.displayName(userId)} handed the group over to you.`,
        { type: 'group_activity', groupId: String(groupId) },
      );
    } catch (err) {
      console.error('[Groups] ownership notification failed:', err);
    }
  })();
  return res.json({ message: 'Ownership transferred' });
}

/** DELETE /api/groups/:id/members/:userId — owner removes a member (kick). */
export async function removeMemberByOwner(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const targetId = String(req.params.userId);
  const group = await requireOwner(groupId, userId, res);
  if (!group) return;
  if (targetId === userId || targetId === String(group.owner_id)) {
    return res.status(400).json({ message: 'The owner can\'t be removed — transfer ownership or disband instead' });
  }
  if (!(await GroupModel.isMember(groupId, targetId))) {
    return res.status(404).json({ message: 'That person isn\'t in this group' });
  }
  // Their frozen split rows stay, so past balances are preserved (like leaving).
  await GroupModel.removeMember(groupId, targetId);
  void emitGroupChanged(groupId);
  void (async () => {
    try {
      await sendPushToUser(
        targetId,
        `Removed from ${group.name}`,
        'The group owner removed you from the group.',
        { type: 'group_activity', groupId: String(groupId) },
      );
    } catch (err) {
      console.error('[Groups] kick notification failed:', err);
    }
  })();
  return res.json({ message: 'Member removed' });
}

/**
 * DELETE /api/groups/:id/leave — leave a group. If the owner leaves, the whole
 * group is disbanded (members cascade); otherwise just their membership is removed.
 */
export async function leaveGroup(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);

  const group = await GroupModel.findById(groupId);
  if (!group) return res.status(404).json({ message: 'Group not found' });
  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }

  if (String(group.owner_id) === userId) {
    // Notify everyone BEFORE the cascade wipes the membership rows.
    const memberIds = await GroupModel.memberIds(groupId);
    // Disband: revert shared expenses to private + drop their splits so nothing
    // is orphaned pointing at a dead group, then delete (cascades members).
    await sql.transaction((txn: any) => [
      txn`DELETE FROM group_expense_splits WHERE group_id = ${groupId}`,
      txn`UPDATE transactions SET group_id = NULL WHERE group_id = ${groupId}`,
      txn`UPDATE goals SET group_id = NULL WHERE group_id = ${groupId}`,
      txn`DELETE FROM groups WHERE id = ${groupId}`,
    ]);
    for (const memberId of memberIds) emitToUser(memberId, 'group:changed', { groupId: Number(groupId) });
    return res.status(200).json({ message: 'Group disbanded' });
  }

  await GroupModel.removeMember(groupId, userId);
  void emitGroupChanged(groupId);
  return res.status(200).json({ message: 'Left group' });
}
