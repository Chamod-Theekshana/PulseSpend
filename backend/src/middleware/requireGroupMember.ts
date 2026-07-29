import type { NextFunction, Response } from 'express';
import { GroupModel } from '../models/GroupModel';
import { GroupMembershipCache } from '../config/groupMembershipCache';
import type { AuthedRequest } from './requireAuth';

/**
 * Confirms the signed-in user actually belongs to the group named by
 * `req.params[paramName]`, 403 otherwise.
 *
 * The chat routes previously mounted `requireAuth` alone, which meant *any*
 * signed-in user could read or post to *any* group's chat just by guessing the
 * numeric id — the group's private conversation and every shared-expense
 * amount in it. Every other group route already did this check inline; the
 * message sub-router was the one that didn't.
 */
export function requireGroupMember(paramName = 'id') {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = String(req.user?.id ?? '');
      const groupId = String((req.params as any)?.[paramName] ?? '');
      if (!userId || !groupId) {
        return res.status(403).json({ message: 'You are not a member of this group' });
      }

      let isMember = GroupMembershipCache.get(groupId, userId);
      if (isMember === null) {
        isMember = await GroupModel.isMember(groupId, userId);
        GroupMembershipCache.set(groupId, userId, isMember);
      }

      if (!isMember) {
        return res.status(403).json({ message: 'You are not a member of this group' });
      }
      return next();
    } catch (err) {
      return next(err);
    }
  };
}
