import { Response } from 'express';
import { redis } from '../config/upstash';
import { ChatModel } from '../models/ChatModel';
import { emitToGroup } from '../socket';
import type { AuthedRequest } from '../middleware/requireAuth';

const CACHE_LIMIT = 50;
const CACHE_TTL = 3600; // 1 hour
const MAX_CONTENT_LENGTH = 4000;

/** Cache key for a group's recent-message window. */
const cacheKeyFor = (groupId: string) => `chat:group:${groupId}`;

/**
 * POST /api/groups/:id/messages
 * Sends a message to a group chat. Persists in DB, prepends to the Redis cache,
 * and broadcasts to everyone currently in the room.
 *
 * Membership is enforced by `requireGroupMember` on the route.
 */
export const sendGroupMessage = async (req: AuthedRequest, res: Response): Promise<Response> => {
  const groupId = String(req.params.id);
  // requireAuth populates `req.user`, NOT `req.userId`. Reading the latter
  // meant every REST-sent message was written with an undefined sender, so it
  // rendered as somebody else's message on every client and broke `isMe`.
  const userId = String(req.user!.id);
  const { content, metadata } = req.body ?? {};

  if (!content || typeof content !== 'string' || content.trim().length === 0) {
    return res.status(400).json({ error: 'Message content is required' });
  }
  const text = content.trim();
  if (text.length > MAX_CONTENT_LENGTH) {
    return res.status(400).json({ error: 'Message is too long' });
  }
  if (metadata !== undefined && metadata !== null && typeof metadata !== 'object') {
    return res.status(400).json({ error: 'metadata must be an object' });
  }

  try {
    const message = await ChatModel.sendMessage(groupId, userId, text, metadata ?? null);
    const apiMessage = ChatModel.toApiShape(message);

    // Prepend to cache so the next fetch picks it up. The TTL is refreshed on
    // every write — without it the key created here never expired, so a group
    // that went quiet kept a stale window forever.
    const cacheKey = cacheKeyFor(groupId);
    try {
      await redis.lpush(cacheKey, JSON.stringify(apiMessage));
      await redis.ltrim(cacheKey, 0, CACHE_LIMIT - 1);
      await redis.expire(cacheKey, CACHE_TTL);
    } catch (cacheErr) {
      // A Redis blip must not lose a message that is already durably stored.
      console.error('[Chat] cache write failed:', cacheErr);
    }

    // Previously this path never broadcast, so a message sent over REST (the
    // offline-retry path, or any client that isn't holding a live socket) was
    // invisible to everyone else until they manually reloaded the screen.
    emitToGroup(groupId, 'new_message', apiMessage);

    return res.status(201).json({ data: apiMessage });
  } catch (error) {
    console.error('[Chat] send failed:', error);
    return res.status(500).json({ error: 'Failed to send message' });
  }
};

/**
 * GET /api/groups/:id/messages?before=<id>&limit=<n>
 * Retrieves paginated messages for a group chat.
 * Uses integer `before` (message ID) for cursor-based pagination.
 */
export const getGroupMessages = async (req: AuthedRequest, res: Response): Promise<Response> => {
  const groupId = String(req.params.id);
  const { before, limit = 30 } = req.query;
  const requested = Number(limit);
  const parsedLimit = Number.isFinite(requested) && requested > 0 ? Math.min(requested, 100) : 30;
  const beforeRaw = before !== undefined ? Number(before) : NaN;
  const beforeId = Number.isInteger(beforeRaw) && beforeRaw > 0 ? beforeRaw : undefined;
  const cacheKey = cacheKeyFor(groupId);

  try {
    // 1. Upstash Redis cache hit (only for the initial load — no cursor).
    if (!beforeId) {
      let cachedMessages: unknown[] | null = null;
      try {
        cachedMessages = await redis.lrange(cacheKey, 0, parsedLimit - 1);
      } catch (cacheErr) {
        console.error('[Chat] cache read failed:', cacheErr);
      }
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

    // 2. Database fallback.
    const dbMessages = await ChatModel.getMessages(groupId, parsedLimit, beforeId);
    const apiMessages = dbMessages.map((msg) => ChatModel.toApiShape(msg));

    // 3. Warm the Redis cache (only for the initial load).
    if (!beforeId && apiMessages.length > 0) {
      try {
        const pipeline = redis.pipeline();
        pipeline.del(cacheKey);
        // apiMessages is newest-first (DESC by id); rpush in that order so the
        // cache-hit branch's lrange(0, n) above keeps reading newest-first.
        apiMessages.forEach((msg) => {
          pipeline.rpush(cacheKey, JSON.stringify(msg));
        });
        pipeline.ltrim(cacheKey, 0, CACHE_LIMIT - 1);
        pipeline.expire(cacheKey, CACHE_TTL);
        await pipeline.exec();
      } catch (cacheErr) {
        console.error('[Chat] cache warm failed:', cacheErr);
      }
    }

    const nextCursor = apiMessages.length === parsedLimit
      ? apiMessages[apiMessages.length - 1].id
      : null;

    return res.status(200).json({ source: 'database', data: apiMessages, nextCursor });
  } catch (error) {
    console.error('[Chat] fetch failed:', error);
    return res.status(500).json({ error: 'Failed to fetch messages' });
  }
};
