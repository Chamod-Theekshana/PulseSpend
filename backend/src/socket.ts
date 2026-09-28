import http from 'http';
import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from './utils/jwt';
import { GroupModel } from './models/GroupModel';
import { ChatModel } from './models/ChatModel';
import { UserModel } from './models/UserModel';
import { TokenVersionCache } from './config/tokenVersionCache';
import { GroupMembershipCache } from './config/groupMembershipCache';
import { redis } from './config/upstash';

const CHAT_CACHE_LIMIT = 50;
const CHAT_CACHE_TTL = 3600; // 1 hour, mirrors chatController's cache window
const MAX_CONTENT_LENGTH = 4000;

/** Per-socket flood control for chat sends. */
const SEND_WINDOW_MS = 10_000;
const SEND_MAX_PER_WINDOW = 30;

/** Cap on rooms per socket, so a buggy/hostile client can't join thousands. */
const MAX_ROOMS_PER_SOCKET = 50;

interface AuthenticatedSocket extends Socket {
  userId?: string;
  /**
   * Groups this socket asked to be in. Kept so we can re-join them ourselves
   * after a transport-level reconnect that Socket.IO could not recover — the
   * old code relied on the client re-emitting `join_group`, which it never did,
   * so a chat silently went deaf after the first network blip.
   */
  joinedGroups?: Set<string>;
  sendWindowStart?: number;
  sendCount?: number;
}

interface AckResponse {
  status: 'success' | 'error';
  message?: string;
  [key: string]: unknown;
}

let ioInstance: Server | null = null;

/** Membership check that goes through the short-TTL cache. */
async function isMemberCached(groupId: string, userId: string): Promise<boolean> {
  const cached = GroupMembershipCache.get(groupId, userId);
  if (cached !== null) return cached;
  const fresh = await GroupModel.isMember(groupId, userId);
  GroupMembershipCache.set(groupId, userId, fresh);
  return fresh;
}

/** Normalises `{ groupId }` / `'123'` / `123` into a clean numeric-string id. */
function parseGroupId(data: unknown): string | null {
  const raw =
    data && typeof data === 'object' && 'groupId' in (data as any)
      ? (data as any).groupId
      : data;
  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? String(id) : null;
}

function withinSendRate(socket: AuthenticatedSocket): boolean {
  const now = Date.now();
  if (!socket.sendWindowStart || now - socket.sendWindowStart > SEND_WINDOW_MS) {
    socket.sendWindowStart = now;
    socket.sendCount = 0;
  }
  socket.sendCount = (socket.sendCount ?? 0) + 1;
  return socket.sendCount <= SEND_MAX_PER_WINDOW;
}

export const configureSocket = (io: Server): void => {
  ioInstance = io;

  // 1. Handshake authentication middleware
  //
  // This must apply exactly the same checks as `requireAuth` does for REST.
  // It previously did not, in two ways that both mattered:
  //
  //   a) It called `jwt.verify` directly instead of `verifyAccessToken`, so it
  //      never enforced the `type: 'access'` claim. A REFRESH token — valid for
  //      30 days — was accepted as socket credentials.
  //   b) It never checked `tokenVersion`. That field is what makes "log out
  //      everywhere" / "revoke sessions" work: bumping it invalidates issued
  //      tokens. The socket ignored it, so a revoked session kept its realtime
  //      connection (and its group-chat access) alive until the token expired
  //      on its own.
  io.use(async (socket: AuthenticatedSocket, next) => {
    const token =
      socket.handshake.auth?.token ||
      socket.handshake.headers['authorization']?.split(' ')[1];

    if (!token) {
      const err: any = new Error('Authentication error: Token missing');
      err.data = { code: 'TOKEN_MISSING' };
      return next(err);
    }

    let user;
    try {
      // Enforces signature, expiry AND the access-token type claim.
      user = verifyAccessToken(token);
    } catch (e: any) {
      // The client needs to tell "my 15-minute access token aged out, refresh
      // and retry" apart from "this token is garbage, sign in again".
      // Socket.IO does NOT auto-reconnect after a middleware rejection, so
      // without this distinction an expired token killed the socket for the
      // rest of the app session.
      const expired = e?.name === 'TokenExpiredError';
      const err: any = new Error(
        expired ? 'Authentication error: Token expired' : 'Authentication error: Invalid token',
      );
      err.data = { code: expired ? 'TOKEN_EXPIRED' : 'TOKEN_INVALID' };
      return next(err);
    }

    try {
      const userId = String(user.id);
      let tokenVersion = TokenVersionCache.get(userId);
      if (tokenVersion === null) {
        tokenVersion = await UserModel.getTokenVersion(userId);
        if (tokenVersion !== null) TokenVersionCache.set(userId, tokenVersion);
      }
      if (tokenVersion === null || tokenVersion !== (user.tokenVersion || 0)) {
        const err: any = new Error('Authentication error: Session revoked');
        // Treated as TOKEN_INVALID by the client: refreshing won't help, the
        // session is genuinely gone and the user must sign in again.
        err.data = { code: 'TOKEN_INVALID' };
        return next(err);
      }

      socket.userId = userId;
      socket.joinedGroups = new Set();
      return next();
    } catch (e) {
      // A database blip during the version lookup must not be reported as bad
      // credentials — that would sign the user out over a transient failure.
      console.error('[Socket] auth check failed:', e);
      const err: any = new Error('Authentication error: Service unavailable');
      err.data = { code: 'AUTH_UNAVAILABLE' };
      return next(err);
    }
  });

  io.on('connection', (socket: AuthenticatedSocket) => {
    if (!socket.joinedGroups) socket.joinedGroups = new Set();

    if (socket.userId) {
      socket.join(`user_${socket.userId}`);
    }

    // When Socket.IO recovered the session it also restored the rooms, so the
    // client does not need to re-join. Tell it which state it's in so it can
    // skip (or perform) the re-join round-trip — this is what stops the
    // reconnect storm after a deploy or a Wi-Fi flap.
    socket.emit('connection_ready', {
      recovered: socket.recovered === true,
      userId: socket.userId,
    });

    // 2. Room authorization & joining
    socket.on('join_group', async (data: any, callback?: (res: AckResponse) => void) => {
      try {
        if (!socket.userId) {
          return callback?.({ status: 'error', message: 'User not authenticated' });
        }

        const groupId = parseGroupId(data);
        if (!groupId) {
          return callback?.({ status: 'error', message: 'Invalid group id' });
        }

        if (
          !socket.joinedGroups!.has(groupId) &&
          socket.joinedGroups!.size >= MAX_ROOMS_PER_SOCKET
        ) {
          return callback?.({ status: 'error', message: 'Too many open groups' });
        }

        if (!(await isMemberCached(groupId, socket.userId))) {
          return callback?.({ status: 'error', message: 'Unauthorized room access' });
        }

        const roomName = `group_${groupId}`;
        await socket.join(roomName);
        socket.joinedGroups!.add(groupId);
        callback?.({ status: 'success', message: `Successfully joined ${roomName}`, groupId });
      } catch (error) {
        console.error('[Socket] join_group failed:', error);
        callback?.({ status: 'error', message: 'Server error verifying membership' });
      }
    });

    // 3. Handle leaving a room
    socket.on('leave_group', async (data: any, callback?: (res: AckResponse) => void) => {
      const groupId = parseGroupId(data);
      if (!groupId) return callback?.({ status: 'error', message: 'Invalid group id' });
      await socket.leave(`group_${groupId}`);
      socket.joinedGroups!.delete(groupId);
      callback?.({ status: 'success', groupId });
    });

    // 4. Message broadcasting
    socket.on('send_message', async (payload: any, callback?: (res: AckResponse) => void) => {
      const localId = payload?.localId;
      try {
        if (!socket.userId) {
          return callback?.({ status: 'error', message: 'User not authenticated', localId });
        }
        if (!withinSendRate(socket)) {
          return callback?.({ status: 'error', message: 'Slow down a moment', localId });
        }

        const groupId = parseGroupId(payload?.groupId);
        if (!groupId) {
          return callback?.({ status: 'error', message: 'Invalid group id', localId });
        }

        const content = typeof payload?.content === 'string' ? payload.content.trim() : '';
        if (!content) {
          return callback?.({ status: 'error', message: 'Message content is required', localId });
        }
        if (content.length > MAX_CONTENT_LENGTH) {
          return callback?.({ status: 'error', message: 'Message is too long', localId });
        }

        const metadata =
          payload?.metadata && typeof payload.metadata === 'object' ? payload.metadata : null;

        if (!(await isMemberCached(groupId, socket.userId))) {
          return callback?.({ status: 'error', message: 'Unauthorized', localId });
        }

        // Persist first — previously this only broadcast in-memory, so a
        // message was lost forever for any recipient who wasn't connected
        // at that exact moment, and history vanished on reconnect/reload.
        const saved = await ChatModel.sendMessage(groupId, socket.userId, content, metadata);
        const apiMessage = ChatModel.toApiShape(saved);

        // Keep the REST cache warm so GET /messages reflects real-time sends.
        // Wrapped: a Redis outage must not fail a message that is already
        // durably in Postgres.
        try {
          const cacheKey = `chat:group:${groupId}`;
          await redis.lpush(cacheKey, JSON.stringify(apiMessage));
          await redis.ltrim(cacheKey, 0, CHAT_CACHE_LIMIT - 1);
          await redis.expire(cacheKey, CHAT_CACHE_TTL);
        } catch (cacheErr) {
          console.error('[Socket] chat cache write failed:', cacheErr);
        }

        // Broadcast to the room. `socket.to(...)` excludes only THIS socket, so
        // the sender's own other devices still receive it — which is what we
        // want, since only this device holds the optimistic copy.
        socket.to(`group_${groupId}`).emit('new_message', {
          ...apiMessage,
          localId,
        });

        // Acknowledge receipt to the sender with the real message id
        callback?.({
          status: 'success',
          messageId: apiMessage.id,
          timestamp: apiMessage.timestamp,
          localId,
        });
      } catch (error) {
        console.error('[Socket] send_message failed:', error);
        callback?.({ status: 'error', message: 'Failed to send message', localId });
      }
    });

    socket.on('error', (err) => {
      console.error(`[Socket] transport error for ${socket.userId}:`, err?.message ?? err);
    });

    socket.on('disconnect', (reason) => {
      if (process.env.NODE_ENV !== 'production') {
        console.log(`[Socket] Client disconnected: ${socket.userId} (${reason})`);
      }
    });
  });
};

export const emitToUser = (userId: string, event: string, payload: any): void => {
  if (ioInstance) {
    ioInstance.to(`user_${userId}`).emit(event, payload);
  }
};

/** Broadcasts to everyone currently in a group's chat room. */
export const emitToGroup = (groupId: string | number, event: string, payload: any): void => {
  if (ioInstance) {
    ioInstance.to(`group_${groupId}`).emit(event, payload);
  }
};

export const getIO = (): Server | null => ioInstance;

/**
 * Creates a Socket.IO server and wires up authentication + room handling.
 * Called from server.ts with the raw http.Server instance.
 */
export const initSocket = (server: http.Server): Server => {
  const io = new Server(server, {
    cors: {
      origin: process.env.CORS_ORIGIN
        ? process.env.CORS_ORIGIN.split(',').map((s) => s.trim()).filter(Boolean)
        : [],
      methods: ['GET', 'POST'],
      credentials: true,
    },
    // Lets a client that dropped for up to two minutes resume the SAME session:
    // rooms are restored and packets missed while away are replayed. This is
    // the single biggest win for flaky mobile networks — without it every
    // tunnel, lift or handover meant a full re-auth + re-join + refetch.
    connectionStateRecovery: {
      maxDisconnectionDuration: 2 * 60 * 1000,
      skipMiddlewares: false,
    },
    // Defaults (25 s / 20 s) are tuned for desktop browsers. On mobile the app
    // is regularly backgrounded mid-interval, and a slow heartbeat means the
    // server keeps dead sockets around — each one still holding room state and
    // still being written to. Faster pings evict them sooner, which is what
    // keeps memory and fan-out sane when many devices connect at once.
    pingInterval: 20_000,
    pingTimeout: 25_000,
    // 1 MB is plenty for chat; the default 1e6 is fine but being explicit stops
    // a malformed client from being handed a bigger buffer than we intend.
    maxHttpBufferSize: 1e6,
    // Allow the polling fallback for networks that block raw WebSocket. The
    // client should still *prefer* websocket; this is a safety net, not a
    // default path.
    transports: ['websocket', 'polling'],
  });

  void attachScaleAdapter(io);

  configureSocket(io);
  return io;
};

/**
 * Optional multi-instance fan-out.
 *
 * Socket.IO rooms live in the memory of ONE process. The moment the service
 * runs more than a single instance (a Render scale-up, or even a rolling
 * deploy where old and new overlap), `emitToUser` / `emitToGroup` only reach
 * the members who happen to be connected to the same instance as the sender —
 * so messages and `group:changed` refreshes appear to "randomly not arrive"
 * for some devices. That is a scaling cliff, and it looks exactly like a
 * connection problem from the app.
 *
 * The fix is a pub/sub adapter. It is wired here behind `REDIS_URL` and
 * imported dynamically so the app still builds and boots without the optional
 * dependency installed:
 *
 *     npm i @socket.io/redis-adapter redis
 *     REDIS_URL=rediss://...            # a TCP Redis, NOT the Upstash REST URL
 *
 * Note: the Upstash *REST* client used elsewhere in this codebase cannot do
 * pub/sub, which is why this needs its own connection string.
 */
async function attachScaleAdapter(io: Server): Promise<void> {
  const url = process.env.REDIS_URL;
  if (!url) {
    if (process.env.NODE_ENV === 'production') {
      console.warn(
        '[Socket] REDIS_URL not set — realtime fan-out is single-instance only. ' +
          'Do not scale beyond one instance without it.',
      );
    }
    return;
  }
  try {
    const [{ createAdapter }, { createClient }] = await Promise.all([
      import('@socket.io/redis-adapter' as any),
      import('redis' as any),
    ]);
    const pubClient = createClient({ url });
    const subClient = pubClient.duplicate();
    pubClient.on('error', (e: any) => console.error('[Socket] redis pub error:', e?.message));
    subClient.on('error', (e: any) => console.error('[Socket] redis sub error:', e?.message));
    await Promise.all([pubClient.connect(), subClient.connect()]);
    io.adapter(createAdapter(pubClient, subClient));
    console.log('[Socket] Redis adapter attached — realtime fan-out is multi-instance safe.');
  } catch (err: any) {
    console.error(
      '[Socket] Could not attach the Redis adapter (falling back to single-instance):',
      err?.message,
    );
  }
}
