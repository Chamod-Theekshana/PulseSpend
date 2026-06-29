import { Server } from 'socket.io';
import type http from 'http';
import { verifyAccessToken } from './utils/jwt';
import { UserModel } from './models/UserModel';

let io: Server | null = null;

export function initSocket(server: http.Server) {
  const allowedOrigins = process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(',').map((s) => s.trim()).filter(Boolean)
    : [];
  const allowAll = allowedOrigins.includes('*') && process.env.NODE_ENV !== 'production';

  io = new Server(server, {
    cors: {
      origin: allowAll ? '*' : allowedOrigins,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    },
  });

  io.use(async (socket, next) => {
    try {
      const token = (socket.handshake.auth as any)?.token;
      if (!token) return next(new Error('Unauthorized'));
      const user = verifyAccessToken(String(token));
      const tokenVersion = await UserModel.getTokenVersion(String(user.id));
      if (tokenVersion === null || tokenVersion !== (user.tokenVersion || 0)) {
        return next(new Error('Unauthorized'));
      }
      (socket as any).user = user;
      return next();
    } catch {
      return next(new Error('Unauthorized'));
    }
  });

  io.on('connection', (socket) => {
    const user = (socket as any).user;
    if (user?.id) {
      socket.join(`user:${user.id}`);
    }
  });

  return io;
}

export function emitToUser(userId: string | number, event: string, payload: any) {
  if (!io) return;
  io.to(`user:${userId}`).emit(event, payload);
}
