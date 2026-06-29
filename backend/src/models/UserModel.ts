import { sql } from '../config/db';

export interface User {
  id: number;
  email: string;
  password: string;
  name?: string | null;
  profile_photo?: string | null;
  theme?: 'dark' | 'light' | string | null;
  currency?: string | null;
  date_format?: string | null;
  language?: string | null;
  first_name?: string | null;
  surname?: string | null;
  date_of_birth?: Date | string | null;
  gender?: string | null;
  contact_no?: string | null;
  biometric_enabled?: boolean | null;
  created_at?: Date;
  token_version?: number | null;
}

export class UserModel {
  static async findByEmail(email: string): Promise<User | null> {
    const result = await sql`SELECT * FROM users WHERE email = ${email}`;
    return (result[0] as User) || null;
  }

  static async findById(id: string): Promise<User | null> {
    const result = await sql`SELECT * FROM users WHERE id = ${id}`;
    return (result[0] as User) || null;
  }

  static async create(email: string, hashedPassword: string): Promise<User> {
    const result = await sql`
      INSERT INTO users (email, password)
      VALUES (${email}, ${hashedPassword})
      RETURNING *
    `;
    return result[0] as User;
  }

  /**
   * Updates profile fields. Any field not provided will remain unchanged.
   * Uses COALESCE to keep existing values.
   */
  static async updateProfile(
    userId: string,
    updates: {
      name?: string;
      profile_photo?: string;
      theme?: string;
      currency?: string;
      date_format?: string;
      language?: string;
      first_name?: string;
      surname?: string;
      date_of_birth?: Date | string;
      gender?: string;
      contact_no?: string;
      biometric_enabled?: boolean;
    }
  ): Promise<User> {
    const hasAny =
      updates.name !== undefined ||
      updates.profile_photo !== undefined ||
      updates.theme !== undefined ||
      updates.currency !== undefined ||
      updates.date_format !== undefined ||
      updates.language !== undefined ||
      updates.first_name !== undefined ||
      updates.surname !== undefined ||
      updates.date_of_birth !== undefined ||
      updates.gender !== undefined ||
      updates.contact_no !== undefined ||
      updates.biometric_enabled !== undefined;

    if (!hasAny) {
      const result = await sql`SELECT * FROM users WHERE id = ${userId}`;
      return result[0] as User;
    }

    const result = await sql`
      UPDATE users
      SET
        name = COALESCE(${updates.name ?? null}, name),
        profile_photo = COALESCE(${updates.profile_photo ?? null}, profile_photo),
        theme = COALESCE(${updates.theme ?? null}, theme),
        currency = COALESCE(${updates.currency ?? null}, currency),
        date_format = COALESCE(${updates.date_format ?? null}, date_format),
        language = COALESCE(${updates.language ?? null}, language),
        first_name = COALESCE(${updates.first_name ?? null}, first_name),
        surname = COALESCE(${updates.surname ?? null}, surname),
        date_of_birth = COALESCE(${updates.date_of_birth ?? null}, date_of_birth),
        gender = COALESCE(${updates.gender ?? null}, gender),
        contact_no = COALESCE(${updates.contact_no ?? null}, contact_no),
        biometric_enabled = COALESCE(${updates.biometric_enabled ?? null}, biometric_enabled)
      WHERE id = ${userId}
      RETURNING *
    `;

    return result[0] as User;
  }

  static async updatePassword(userId: string, hashedPassword: string): Promise<void> {
    await sql`UPDATE users SET password = ${hashedPassword} WHERE id = ${userId}`;
  }

  static async getTokenVersion(userId: string): Promise<number | null> {
    const result = await sql`SELECT token_version FROM users WHERE id = ${userId}`;
    const row = result[0] as any;
    if (!row) return null;
    return Number(row.token_version || 0);
  }

  static async incrementTokenVersion(userId: string): Promise<number> {
    const result = await sql`
      UPDATE users
      SET token_version = COALESCE(token_version, 0) + 1
      WHERE id = ${userId}
      RETURNING token_version
    `;
    const row = result[0] as any;
    return Number(row?.token_version || 0);
  }
}
