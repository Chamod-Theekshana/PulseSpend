import { Request, Response } from 'express';
import { sql } from '../config/db';

/**
 * GET /api/notifications/history
 * Returns the user's notification inbox (latest 50 by default).
 * Also returns the unread count so the client can show the badge.
 */
export async function getNotificationHistory(req: Request, res: Response) {
  const user_id = String((req as any).user?.id);
  const limit  = Math.min(parseInt(req.query.limit  as string) || 50, 100);
  const offset = parseInt(req.query.offset as string) || 0;

  const [rows, countRows] = await Promise.all([
    sql`
      SELECT id, title, body, type, data, read, created_at
      FROM notifications
      WHERE user_id = ${user_id}
      ORDER BY created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `,
    sql`
      SELECT COUNT(*) AS count
      FROM notifications
      WHERE user_id = ${user_id} AND read = false
    `,
  ]);

  return res.json({
    notifications: rows,
    unreadCount: parseInt((countRows[0] as any)?.count || '0'),
  });
}

/**
 * PATCH /api/notifications/mark-all-read
 * Marks every unread notification for this user as read.
 */
export async function markAllRead(req: Request, res: Response) {
  const user_id = String((req as any).user?.id);
  await sql`
    UPDATE notifications
    SET read = true
    WHERE user_id = ${user_id} AND read = false
  `;
  return res.json({ status: 200, message: 'All notifications marked as read' });
}

/**
 * PATCH /api/notifications/:id/read
 * Marks a single notification as read.
 */
export async function markOneRead(req: Request, res: Response) {
  const user_id = String((req as any).user?.id);
  const id = parseInt(req.params.id as string);
  if (!id) return res.status(400).json({ message: 'Invalid notification id' });

  await sql`
    UPDATE notifications
    SET read = true
    WHERE id = ${id} AND user_id = ${user_id}
  `;
  return res.json({ status: 200, message: 'Notification marked as read' });
}

/**
 * DELETE /api/notifications/clear
 * Deletes ALL notifications for this user (clear inbox).
 */
export async function clearNotifications(req: Request, res: Response) {
  const user_id = String((req as any).user?.id);
  await sql`DELETE FROM notifications WHERE user_id = ${user_id}`;
  return res.json({ status: 200, message: 'Notifications cleared' });
}
