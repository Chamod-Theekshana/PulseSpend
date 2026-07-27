import { Request, Response } from 'express';
import { redis } from '../config/upstash';
import { ChatModel } from '../models/ChatModel';

const CACHE_LIMIT = 50;
const CACHE_TTL = 3600; // 1 hour

/**
 * POST /api/groups/:id/messages
 * Sends a message to a group chat. Persists in DB and prepends to the Redis cache.
 */
export const sendGroupMessage = async (req: Request, res: Response): Promise<Response> => {
  const groupId = req.params.id;
  const userId = (req as any).userId;
  const { content } = req.body;

  if (!content || typeof content !== 'string' || content.trim().length === 0) {
    return res.status(400).json({ error: 'Message content is required' });
  }

  try {
    const message = await ChatModel.sendMessage(groupId, userId, content.trim());

    // Prepend to cache so next fetch picks it up
    const cacheKey = `chat:group:${groupId}`;
    await redis.lpush(cacheKey, JSON.stringify(message));
    await redis.ltrim(cacheKey, 0, CACHE_LIMIT - 1);

    return res.status(201).json({ data: message });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to send message' });
  }
};

/**
 * GET /api/groups/:id/messages?before=<id>&limit=<n>
 * Retrieves paginated messages for a group chat.
 * Uses integer `before` (message ID) for cursor-based pagination.
 */
export const getGroupMessages = async (req: Request, res: Response): Promise<Response> => {
  const groupId = req.params.id;
  const { before, limit = 30 } = req.query;
  const parsedLimit = Math.min(Number(limit), 100);
  const beforeId = before ? Number(before) : undefined;
  const cacheKey = `chat:group:${groupId}`;

  try {
    // 1. Upstash Redis Cache hit (only for initial load — no cursor)
    if (!beforeId) {
      const cachedMessages = await redis.lrange(cacheKey, 0, parsedLimit - 1);
      if (cachedMessages && cachedMessages.length > 0) {
        const messages = cachedMessages.map((msg) =>
          typeof msg === 'string' ? JSON.parse(msg) : msg
        );
        const nextCursor = messages.length === parsedLimit
          ? messages[messages.length - 1].id
          : null;
        return res.status(200).json({
          source: 'cache',
          data: messages,
          nextCursor,
        });
      }
    }

    // 2. Database Fallback
    const dbMessages = await ChatModel.getMessages(groupId, parsedLimit, beforeId);

    // 3. Warm the Redis cache (only for initial load)
    if (!beforeId && dbMessages.length > 0) {
      const pipeline = redis.pipeline();
      pipeline.del(cacheKey);
      dbMessages.forEach((msg) => {
        pipeline.rpush(cacheKey, JSON.stringify(msg));
      });
      pipeline.ltrim(cacheKey, 0, CACHE_LIMIT - 1);
      pipeline.expire(cacheKey, CACHE_TTL);
      await pipeline.exec();
    }

    const nextCursor = dbMessages.length === parsedLimit
      ? dbMessages[dbMessages.length - 1].id
      : null;

    return res.status(200).json({ source: 'database', data: dbMessages, nextCursor });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to fetch messages' });
  }
};