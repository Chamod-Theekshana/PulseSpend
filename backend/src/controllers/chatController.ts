import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';
import { ChatModel } from '../models/ChatModel';
import { GroupModel } from '../models/GroupModel';
import { emitToUser } from '../socket';

/**
 * Validates that the user is a member of the group.
 * Returns the array of all member IDs so we can broadcast to them.
 */
async function requireMembershipAndGetMembers(groupId: string, userId: string, res: Response): Promise<string[] | null> {
  const group = await GroupModel.findById(groupId);
  if (!group) {
    res.status(404).json({ message: 'Group not found' });
    return null;
  }
  const members = await GroupModel.memberIds(groupId);
  if (!members.includes(userId)) {
    res.status(403).json({ message: 'Access denied: not a group member' });
    return null;
  }
  return members;
}

export const sendMessage = async (req: AuthedRequest, res: Response): Promise<void> => {
  const id = req.params.id as string; // groupId
  const { content } = req.body;
  const userId = String(req.user!.id);

  if (!content || typeof content !== 'string' || content.trim().length === 0) {
    res.status(400).json({ message: 'Message content is required' });
    return;
  }

  if (content.trim().length > 2000) {
    res.status(400).json({ message: 'Message is too long (max 2000 characters)' });
    return;
  }

  const members = await requireMembershipAndGetMembers(id, userId, res);
  if (!members) return;

  try {
    const message = await ChatModel.sendMessage(id, userId, content.trim());
    
    // Broadcast via socket to all members (including sender, though sender could ignore it based on ID)
    for (const memberId of members) {
      emitToUser(memberId, 'group:message', { groupId: Number(id), message });
    }

    res.status(200).json({ message: 'Sent successfully', data: message });
  } catch (err) {
    console.error('[Chat] sendMessage failed:', err);
    res.status(500).json({ message: 'Failed to send message' });
  }
};

export const getMessages = async (req: AuthedRequest, res: Response): Promise<void> => {
  const id = req.params.id as string; // groupId
  const userId = String(req.user!.id);
  const limit = req.query.limit ? parseInt(req.query.limit as string) : 30;
  const beforeId = req.query.before ? parseInt(req.query.before as string) : undefined;

  const members = await requireMembershipAndGetMembers(id, userId, res);
  if (!members) return;

  try {
    const messages = await ChatModel.getMessages(id, limit, beforeId);
    res.status(200).json({ data: messages });
  } catch (err) {
    console.error('[Chat] getMessages failed:', err);
    res.status(500).json({ message: 'Failed to fetch messages' });
  }
};