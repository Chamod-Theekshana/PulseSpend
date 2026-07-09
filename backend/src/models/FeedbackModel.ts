import { sql } from '../config/db';

export interface Feedback {
  id: number;
  user_id: string;
  category: string;
  subject: string;
  message: string;
  email?: string | null;
  app_version?: string | null;
  platform?: string | null;
  status: string;
  created_at?: Date | string;
}

export const FEEDBACK_CATEGORIES = ['problem', 'suggestion', 'question', 'other'];

export class FeedbackModel {
  static async create(
    userId: string,
    data: {
      category: string;
      subject: string;
      message: string;
      email?: string | null;
      app_version?: string | null;
      platform?: string | null;
    }
  ): Promise<Feedback> {
    const rows = await sql`
      INSERT INTO feedback (user_id, category, subject, message, email, app_version, platform)
      VALUES (
        ${userId},
        ${data.category},
        ${data.subject},
        ${data.message},
        ${data.email ?? null},
        ${data.app_version ?? null},
        ${data.platform ?? null}
      )
      RETURNING *
    `;
    return rows[0] as Feedback;
  }

  static async listByUser(userId: string, limit = 50, offset = 0): Promise<Feedback[]> {
    const rows = await sql`
      SELECT * FROM feedback
      WHERE user_id = ${userId}
      ORDER BY created_at DESC
      LIMIT ${limit} OFFSET ${offset}
    `;
    return rows as Feedback[];
  }
}
