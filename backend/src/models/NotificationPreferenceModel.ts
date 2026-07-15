import { sql } from '../config/db';

export interface NotificationPreferences {
  user_id: string;
  push_enabled: boolean;
  bill_reminders: boolean;
  goal_reminders: boolean;
  budget_alerts: boolean;
  recurring_alerts: boolean;
  summary_digest: boolean;
  group_activity: boolean;
  updated_at?: Date | string;
}

const DEFAULTS: Omit<NotificationPreferences, 'user_id' | 'updated_at'> = {
  push_enabled: true,
  bill_reminders: true,
  goal_reminders: true,
  budget_alerts: true,
  recurring_alerts: true,
  summary_digest: true,
  group_activity: true,
};

/** Maps a push `data.type` value to the preference flag that gates it. */
function flagForType(type: string): keyof typeof DEFAULTS | null {
  const t = (type || '').toLowerCase();
  if (t.includes('summary') || t.includes('digest')) return 'summary_digest';
  if (t.includes('group')) return 'group_activity';
  if (t.includes('bill') || t.includes('reminder')) return 'bill_reminders';
  if (t.includes('goal')) return 'goal_reminders';
  if (t.includes('budget')) return 'budget_alerts';
  // Recurring charges + subscription price alerts share the recurring toggle.
  if (t.includes('recurring') || t.includes('subscription')) return 'recurring_alerts';
  return null; // e.g. security / general → always allowed (only gated by push_enabled)
}

export class NotificationPreferenceModel {
  /** Returns the user's prefs, falling back to all-enabled defaults if no row exists. */
  static async get(userId: string): Promise<NotificationPreferences> {
    const rows = await sql`SELECT * FROM notification_preferences WHERE user_id = ${userId}`;
    if (rows[0]) return rows[0] as NotificationPreferences;
    return { user_id: String(userId), ...DEFAULTS };
  }

  /** Upserts the provided fields; unspecified fields keep their current value. */
  static async update(
    userId: string,
    updates: Partial<Omit<NotificationPreferences, 'user_id' | 'updated_at'>>
  ): Promise<NotificationPreferences> {
    const current = await NotificationPreferenceModel.get(userId);
    const next = {
      push_enabled: updates.push_enabled ?? current.push_enabled,
      bill_reminders: updates.bill_reminders ?? current.bill_reminders,
      goal_reminders: updates.goal_reminders ?? current.goal_reminders,
      budget_alerts: updates.budget_alerts ?? current.budget_alerts,
      recurring_alerts: updates.recurring_alerts ?? current.recurring_alerts,
      summary_digest: updates.summary_digest ?? current.summary_digest,
      group_activity: updates.group_activity ?? current.group_activity,
    };

    const rows = await sql`
      INSERT INTO notification_preferences
        (user_id, push_enabled, bill_reminders, goal_reminders, budget_alerts, recurring_alerts, summary_digest, group_activity, updated_at)
      VALUES
        (${userId}, ${next.push_enabled}, ${next.bill_reminders}, ${next.goal_reminders}, ${next.budget_alerts}, ${next.recurring_alerts}, ${next.summary_digest}, ${next.group_activity}, CURRENT_TIMESTAMP)
      ON CONFLICT (user_id) DO UPDATE SET
        push_enabled = EXCLUDED.push_enabled,
        bill_reminders = EXCLUDED.bill_reminders,
        goal_reminders = EXCLUDED.goal_reminders,
        budget_alerts = EXCLUDED.budget_alerts,
        recurring_alerts = EXCLUDED.recurring_alerts,
        summary_digest = EXCLUDED.summary_digest,
        group_activity = EXCLUDED.group_activity,
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `;
    return rows[0] as NotificationPreferences;
  }

  /**
   * Whether a notification of the given `type` should be delivered to the user.
   * `push_enabled = false` mutes everything; otherwise the per-category flag decides.
   */
  static async isAllowed(userId: string, type: string): Promise<boolean> {
    const prefs = await NotificationPreferenceModel.get(userId);
    if (!prefs.push_enabled) return false;
    const flag = flagForType(type);
    if (!flag) return true;
    return Boolean(prefs[flag]);
  }
}
