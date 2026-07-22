import { sql } from '../config/db';

export interface ChatMessage {
  id: number;
  group_id: number;
  user_id: string;
  content: string;
  created_at: Date;
  sender_name?: string; // from users table join
}

export class ChatModel {
  /**
   * Sends a message to a group. Returns the inserted message with the sender's name.
   */
  static async sendMessage(groupId: number | string, userId: string, content: string): Promise<ChatMessage> {
    const rows = await sql`
      WITH inserted AS (
        INSERT INTO group_messages (group_id, user_id, content)
        VALUES (${Number(groupId)}, ${userId}, ${content})
        RETURNING *
      )
      SELECT i.*, u.name as sender_name
      FROM inserted i
      LEFT JOIN users u ON u.id::text = i.user_id
    `;
    return rows[0] as ChatMessage;
  }

  /**
   * Retrieves messages for a group, paginated.
   * If beforeId is provided, returns messages older than that ID.
   * Returns them in descending order (newest first).
   */
  static async getMessages(groupId: number | string, limit: number = 30, beforeId?: number): Promise<ChatMessage[]> {
    if (beforeId) {
      const rows = await sql`
        SELECT m.*, u.name as sender_name
        FROM group_messages m
        LEFT JOIN users u ON u.id::text = m.user_id
        WHERE m.group_id = ${Number(groupId)} AND m.id < ${beforeId}
        ORDER BY m.id DESC
        LIMIT ${limit}
      `;
      return rows as ChatMessage[];
    } else {
      const rows = await sql`
        SELECT m.*, u.name as sender_name
        FROM group_messages m
        LEFT JOIN users u ON u.id::text = m.user_id
        WHERE m.group_id = ${Number(groupId)}
        ORDER BY m.id DESC
        LIMIT ${limit}
      `;
      return rows as ChatMessage[];
    }
  }
}
