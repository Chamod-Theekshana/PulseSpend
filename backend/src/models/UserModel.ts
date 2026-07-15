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
  totp_secret?: string | null;
  totp_enabled?: boolean | null;
  totp_recovery_codes?: string | null;
  deletion_requested_at?: Date | string | null;
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

  /** Friendly display name for notifications: name, else the email local-part. */
  static async displayName(id: string): Promise<string> {
    const rows = await sql`SELECT name, email FROM users WHERE id = ${id}`;
    const u = rows[0] as any;
    if (!u) return 'A member';
    const name = u.name ? String(u.name).trim() : '';
    if (name) return name;
    return String(u.email || 'A member').split('@')[0];
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

  // ── GDPR grace-period deletion ─────────────────────────────────────────────

  /** Marks the account for deletion after the grace period. */
  static async requestDeletion(userId: string): Promise<void> {
    await sql`UPDATE users SET deletion_requested_at = NOW() WHERE id = ${userId}`;
  }

  /** Cancels a pending deletion (user signed back in during the grace window). */
  static async cancelDeletion(userId: string): Promise<void> {
    await sql`UPDATE users SET deletion_requested_at = NULL WHERE id = ${userId}`;
  }

  /** Accounts whose grace period has lapsed and are due for a hard purge. */
  static async listDueForPurge(graceDays: number): Promise<Array<{ id: string; email: string }>> {
    const rows = await sql`
      SELECT id, email FROM users
      WHERE deletion_requested_at IS NOT NULL
        AND deletion_requested_at < NOW() - (${graceDays} || ' days')::interval
    `;
    return rows.map((r: any) => ({ id: String(r.id), email: String(r.email) }));
  }

  // ── TOTP 2FA ───────────────────────────────────────────────────────────────

  /** Stores a pending secret + recovery-code hashes; 2FA stays OFF until verified. */
  static async setTotpSecret(userId: string, secret: string, recoveryHashes: string[]): Promise<void> {
    await sql`
      UPDATE users
      SET totp_secret = ${secret},
          totp_recovery_codes = ${JSON.stringify(recoveryHashes)},
          totp_enabled = false
      WHERE id = ${userId}
    `;
  }

  /** Flips 2FA on after the user proves a working authenticator code. */
  static async enableTotp(userId: string): Promise<void> {
    await sql`UPDATE users SET totp_enabled = true WHERE id = ${userId}`;
  }

  static async disableTotp(userId: string): Promise<void> {
    await sql`
      UPDATE users
      SET totp_secret = NULL, totp_enabled = false, totp_recovery_codes = NULL
      WHERE id = ${userId}
    `;
  }

  /**
   * One-shot recovery code: removes the given hash from the stored list.
   * Returns true only if the hash was present (i.e. the code was valid and
   * unused).
   */
  static async consumeRecoveryCode(userId: string, hash: string): Promise<boolean> {
    const rows = await sql`SELECT totp_recovery_codes FROM users WHERE id = ${userId}`;
    const raw = (rows[0] as any)?.totp_recovery_codes;
    if (!raw) return false;
    let hashes: string[];
    try {
      hashes = JSON.parse(String(raw));
    } catch {
      return false;
    }
    if (!Array.isArray(hashes) || !hashes.includes(hash)) return false;
    const remaining = hashes.filter((h) => h !== hash);
    await sql`UPDATE users SET totp_recovery_codes = ${JSON.stringify(remaining)} WHERE id = ${userId}`;
    return true;
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

  /**
   * Permanently erases the account and every row that belongs to it (GDPR
   * "right to be forgotten"). `transaction_splits` / `transaction_tags` are
   * removed automatically by their `ON DELETE CASCADE` FK when the parent
   * transaction row goes; the remaining tables key off `user_id` so we delete
   * them explicitly. The `users` row is removed last.
   *
   * Neon's HTTP driver runs each statement independently (no cross-statement
   * transaction), so we order deletes children-first to avoid leaving orphans
   * if one call fails midway.
   */
  static async deleteAccount(userId: string): Promise<void> {
    await sql`DELETE FROM transactions WHERE user_id = ${userId}`;
    await sql`DELETE FROM categories WHERE user_id = ${userId}`;
    await sql`DELETE FROM budgets WHERE user_id = ${userId}`;
    await sql`DELETE FROM recurring_transactions WHERE user_id = ${userId}`;
    await sql`DELETE FROM reminders WHERE user_id = ${userId}`;
    await sql`DELETE FROM goals WHERE user_id = ${userId}`;
    await sql`DELETE FROM debts WHERE user_id = ${userId}`;
    await sql`DELETE FROM notifications WHERE user_id = ${userId}`;
    await sql`DELETE FROM notification_preferences WHERE user_id = ${userId}`;
    await sql`DELETE FROM feedback WHERE user_id = ${userId}`;
    await sql`DELETE FROM user_fcm_tokens WHERE user_id = ${userId}`;
    // Group memberships + any groups this user owns (owned groups cascade-remove
    // their remaining members).
    await sql`DELETE FROM group_members WHERE user_id = ${userId}`;
    await sql`DELETE FROM groups WHERE owner_id = ${userId}`;
    await sql`DELETE FROM users WHERE id = ${userId}`;
  }
}
