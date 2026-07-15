import { GroupModel } from '../models/GroupModel';
import { UserModel } from '../models/UserModel';
import { sendPushToUser } from '../services/pushService';
import { sql } from '../config/db';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

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
    GroupModel.aggregatedTransactions(groupId),
    GroupModel.summary(groupId, currency),
  ]);
  return res.status(200).json({ transactions, summary });
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
 * POST /api/groups/:id/settle — record "I paid <to_user> <amount>". Both sides
 * get a group_activity notification and balances shift accordingly.
 */
export async function settleUp(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const groupId = String(req.params.id);
  const { to_user, amount, currency } = req.body ?? {};

  if (!(await GroupModel.isMember(groupId, userId))) {
    return res.status(403).json({ message: 'You are not a member of this group' });
  }
  const toUser = String(to_user ?? '');
  if (!toUser || toUser === userId || !(await GroupModel.isMember(groupId, toUser))) {
    return res.status(400).json({ message: 'to_user must be another member of this group' });
  }
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0 || amt > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }
  const cur = typeof currency === 'string' && currency.trim() ? currency.trim().toUpperCase().slice(0, 10) : 'LKR';

  await GroupModel.createSettlement(groupId, userId, toUser, Math.round(amt * 100) / 100, cur);

  const group = await GroupModel.findById(groupId);
  void (async () => {
    try {
      const payerName = await UserModel.displayName(userId);
      await sendPushToUser(
        toUser,
        `Settled up in ${group?.name ?? 'your group'}`,
        `${payerName} recorded a payment of ${amt.toFixed(2)} ${cur} to you.`,
        { type: 'group_activity', groupId: String(groupId) },
      );
    } catch (err) {
      console.error('[Groups] settle notification failed:', err);
    }
  })();

  return res.status(201).json({ message: 'Settlement recorded' });
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
    await sql`DELETE FROM groups WHERE id = ${groupId}`; // cascade removes members
    return res.status(200).json({ message: 'Group disbanded' });
  }

  await GroupModel.removeMember(groupId, userId);
  return res.status(200).json({ message: 'Left group' });
}
