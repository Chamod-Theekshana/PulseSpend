import http from 'http';
import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { GroupModel } from './models/GroupModel';

interface AuthenticatedSocket extends Socket {
  userId?: string;
}

interface JoinGroupCallback {
  status: 'success' | 'error';
  message: string;
}

let ioInstance: Server | null = null;

export const configureSocket = (io: Server): void => {
  ioInstance = io;
  
  // 1. Handshake Authentication Middleware
  io.use((socket: AuthenticatedSocket, next) => {
    const token =
      socket.handshake.auth?.token ||
      socket.handshake.headers['authorization']?.split(' ')[1];

    if (!token) {
      return next(new Error('Authentication error: Token missing'));
    }

    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET as string) as {
        userId: string;
      };
      socket.userId = decoded.userId;
      next();
    } catch (err) {
      next(new Error('Authentication error: Invalid token'));
    }
  });

  io.on('connection', (socket: AuthenticatedSocket) => {
    console.log(`[Socket] Client connected: ${socket.userId}`);
    if (socket.userId) {
      socket.join(`user_${socket.userId}`);
    }

    // 2. Room Authorization & Joining
    socket.on('join_group', async (data: any, callback?: (res: JoinGroupCallback) => void) => {
        try {
          if (!socket.userId) {
            return callback?.({ status: 'error', message: 'User not authenticated' });
          }

          // Frontend sends { groupId: '...' } via emitWithAck
          const groupId = typeof data === 'object' ? String(data.groupId) : String(data);

          const isMember = await GroupModel.isMember(groupId, socket.userId);
          if (!isMember) {
            return callback?.({ status: 'error', message: 'Unauthorized room access' });
          }

          const roomName = `group_${groupId}`;
          await socket.join(roomName);
          callback?.({ status: 'success', message: `Successfully joined ${roomName}` });
        } catch (error) {
          callback?.({ status: 'error', message: 'Server error verifying membership' });
        }
      }
    );

    // 3. Handle Leaving Room
    socket.on('leave_group', async (data: any) => {
      const groupId = typeof data === 'object' ? String(data.groupId) : String(data);
      await socket.leave(`group_${groupId}`);
    });

    // 4. Message Broadcasting
    socket.on('send_message', async (payload: any, callback?: (res: any) => void) => {
        try {
          if (!socket.userId) return;

          const { groupId, localId } = payload;
          const isMember = await GroupModel.isMember(groupId, socket.userId);

          if (!isMember) {
            return callback?.({ status: 'error', message: 'Unauthorized' });
          }

          // Broadcast to others in the room
          socket.to(`group_${groupId}`).emit('new_message', {
            ...payload,
            senderId: socket.userId,
            timestamp: new Date().toISOString(),
          });

          // Acknowledge receipt to the sender
          callback?.({
            status: 'success',
            messageId: `msg_${Date.now()}_${Math.random().toString(36).substring(7)}`,
            localId,
          });
        } catch (error) {
          callback?.({ status: 'error', message: 'Failed to broadcast' });
        }
      }
    );

    socket.on('disconnect', () => {
      console.log(`[Socket] Client disconnected: ${socket.userId}`);
    });
  });
};

export const emitToUser = (userId: string, event: string, payload: any): void => {
  if (ioInstance) {
    ioInstance.to(`user_${userId}`).emit(event, payload);
  }
};

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
    },
  });
  configureSocket(io);
  return io;
};