import { sql } from '../config/db';

export interface ChatMessage {
  id: number;
  group_id: number;
  user_id: string;
  content: string;
  metadata: Record<string, any> | null;
  created_at: Date;
  sender_name?: string; // from users table join
}

/** Public, camelCase shape the Flutter app's `ChatMessage.fromJson` expects. */
export interface ChatMessageApi {
  id: string;
  groupId: string;
  senderId: string;
  senderName?: string;
  content: string;
  timestamp: string;
  metadata: Record<string, any> | null;
  status: 'sent';
}

export class ChatModel {
  /** Maps a raw DB row (snake_case) to the API shape the client models expect. */
  static toApiShape(row: ChatMessage): ChatMessageApi {
    return {
      id: String(row.id),
      groupId: String(row.group_id),
      senderId: row.user_id,
      senderName: row.sender_name,
      content: row.content,
      timestamp: new Date(row.created_at).toISOString(),
      metadata: row.metadata ?? null,
      status: 'sent',
    };
  }

  /**
   * Sends a message to a group. Returns the inserted message with the sender's name.
   * [metadata] carries structured data for special bubbles (e.g. shared expenses).
   */
  static async sendMessage(
    groupId: number | string,
    userId: string,
    content: string,
    metadata?: Record<string, any> | null,
  ): Promise<ChatMessage> {
    const metadataJson = metadata ? JSON.stringify(metadata) : null;
    const rows = await sql`
      WITH inserted AS (
        INSERT INTO group_messages (group_id, user_id, content, metadata)
        VALUES (${Number(groupId)}, ${userId}, ${content}, ${metadataJson}::jsonb)
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
