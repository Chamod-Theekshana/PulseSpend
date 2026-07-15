import { neon } from "@neondatabase/serverless"
import 'dotenv/config';

const rawSql = neon(process.env.DATABASE_URL!);

const DB_QUERY_RETRIES = 1;          // one extra attempt after the first
const DB_RETRY_BASE_DELAY_MS = 400;

/**
 * Neon's HTTP driver can intermittently fail to reach the database with a
 * transient network error (connect timeout, DNS blip, reset). These mean the
 * query almost certainly never reached the server, so they're safe to retry —
 * unlike an actual SQL error, which we surface immediately.
 */
export function isTransientDbError(err: any): boolean {
  const code =
    err?.sourceError?.cause?.code ||
    err?.cause?.code ||
    err?.code ||
    '';
  const msg = String(err?.message ?? '') + ' ' + String(err?.sourceError?.message ?? '');
  return (
    code === 'UND_ERR_CONNECT_TIMEOUT' ||
    code === 'ECONNRESET' ||
    code === 'ECONNREFUSED' ||
    code === 'ENOTFOUND' ||
    code === 'EAI_AGAIN' ||
    code === 'ETIMEDOUT' ||
    /fetch failed/i.test(msg) ||
    /Error connecting to database/i.test(msg)
  );
}

/**
 * Drop-in replacement for the neon `sql` tagged-template that transparently
 * retries transient connection failures with a short backoff. All models use
 * the tagged form (`sql`...``), so wrapping here makes every query resilient.
 */
export const sql = (async (strings: TemplateStringsArray, ...values: any[]) => {
  let lastErr: any;
  for (let attempt = 0; attempt <= DB_QUERY_RETRIES; attempt++) {
    try {
      return await (rawSql as any)(strings, ...values);
    } catch (err: any) {
      lastErr = err;
      if (!isTransientDbError(err) || attempt === DB_QUERY_RETRIES) break;
      const delay = DB_RETRY_BASE_DELAY_MS * Math.pow(2, attempt);
      console.warn(
        `[DB] Transient error (attempt ${attempt + 1}/${DB_QUERY_RETRIES + 1}), retrying in ${delay}ms:`,
        err?.message,
      );
      await sleep(delay);
    }
  }
  // Tag so the error handler can map it to a clean 503 instead of a 500.
  if (lastErr && isTransientDbError(lastErr)) lastErr.isDbConnectionError = true;
  throw lastErr;
}) as typeof rawSql;

const INIT_RETRIES = 3;
const INIT_RETRY_DELAY_MS = 3000;

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function initDB() {
  let lastError: unknown;

  for (let attempt = 1; attempt <= INIT_RETRIES; attempt++) {
    try {
      await _runMigrations();
      console.log('Database initialized successfully');
      return;
    } catch (error) {
      lastError = error;
      if (attempt < INIT_RETRIES) {
        console.warn(`[DB] Init attempt ${attempt}/${INIT_RETRIES} failed, retrying in ${INIT_RETRY_DELAY_MS / 1000}s...`, (error as any)?.message);
        await sleep(INIT_RETRY_DELAY_MS);
      }
    }
  }

  console.error('Error initializing database', lastError);
  process.exit(1);
}

async function _runMigrations() {

        await sql`CREATE TABLE IF NOT EXISTS users(
            id SERIAL PRIMARY KEY,
            email VARCHAR(255) UNIQUE NOT NULL,
            password VARCHAR(255) NOT NULL,
            name VARCHAR(255),
            profile_photo TEXT,
            theme VARCHAR(20) DEFAULT 'dark',
            currency VARCHAR(10) DEFAULT 'USD',
            date_format VARCHAR(20) DEFAULT 'DD/MM/YYYY',
            biometric_enabled BOOLEAN NOT NULL DEFAULT false,
            token_version INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

        // New users default to following the device (system) theme.
        await sql`ALTER TABLE users ALTER COLUMN theme SET DEFAULT 'system'`;

        // Backward-compatible schema upgrades
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'USD'`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS date_format VARCHAR(20) DEFAULT 'DD/MM/YYYY'`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS language VARCHAR(20) DEFAULT 'English'`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name VARCHAR(255)`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS surname VARCHAR(255)`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS date_of_birth DATE`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS gender VARCHAR(50)`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS contact_no VARCHAR(50)`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS biometric_enabled BOOLEAN NOT NULL DEFAULT false`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0`;

        // FCM tokens table (supports multiple devices per user)
        await sql`CREATE TABLE IF NOT EXISTS user_fcm_tokens(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            token TEXT UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

        await sql`CREATE TABLE IF NOT EXISTS transactions(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            title VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            category VARCHAR(255) NOT NULL,
            created_at DATE NOT NULL DEFAULT CURRENT_DATE
        )`;

        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'LKR'`;
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS notes TEXT`;
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;

        // Idempotency key for offline-created transactions: a client generates a
        // stable id per queued op, so replaying it after a reconnect (or a lost
        // response) never creates a duplicate. Unique per user when present.
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS client_op_id VARCHAR(64)`;
        await sql`CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_user_op ON transactions(user_id, client_op_id) WHERE client_op_id IS NOT NULL`;

        // ── WALLETS / ACCOUNTS ────────────────────────────────────────────────
        // Cash / bank / card accounts. transactions.wallet_id is nullable —
        // NULL means the default wallet (legacy rows keep working untouched).
        await sql`CREATE TABLE IF NOT EXISTS wallets(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            name VARCHAR(100) NOT NULL,
            type VARCHAR(20) NOT NULL DEFAULT 'cash',
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            deleted_at TIMESTAMP,
            UNIQUE(user_id, name)
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id)`;
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS wallet_id INTEGER`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id)`;

        await sql`CREATE TABLE IF NOT EXISTS transaction_splits(
            id SERIAL PRIMARY KEY,
            transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
            user_id VARCHAR(255) NOT NULL,
            category VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            percentage DECIMAL(5,2) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

        await sql`ALTER TABLE transaction_splits ADD COLUMN IF NOT EXISTS percentage DECIMAL(5,2) NOT NULL DEFAULT 0`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_splits_user_id ON transaction_splits(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_splits_transaction_id ON transaction_splits(transaction_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_splits_user_category ON transaction_splits(user_id, category)`;

        await sql`CREATE TABLE IF NOT EXISTS transaction_tags(
            id SERIAL PRIMARY KEY,
            transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
            user_id VARCHAR(255) NOT NULL,
            tag VARCHAR(64) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(transaction_id, tag)
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_tags_user_id ON transaction_tags(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_tags_transaction_id ON transaction_tags(transaction_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transaction_tags_user_tag ON transaction_tags(user_id, tag)`;

        await sql`CREATE TABLE IF NOT EXISTS categories(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            type VARCHAR(20) NOT NULL DEFAULT 'expense',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            deleted_at TIMESTAMP,
            UNIQUE(user_id, name)
        )`;

        await sql`ALTER TABLE categories ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;

        await sql`CREATE TABLE IF NOT EXISTS budgets(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            category VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            period VARCHAR(20) NOT NULL DEFAULT 'monthly',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, category)
        )`;

        await sql`ALTER TABLE budgets ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'LKR'`;
        await sql`ALTER TABLE budgets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;
        // Alert dedupe + pacing state. alert_period is the current window's start
        // date (ISO); alert_level is the highest threshold (80/100) already
        // pushed this period; pace_alerted marks the one pacing alert per period.
        await sql`ALTER TABLE budgets ADD COLUMN IF NOT EXISTS alert_period VARCHAR(10)`;
        await sql`ALTER TABLE budgets ADD COLUMN IF NOT EXISTS alert_level SMALLINT NOT NULL DEFAULT 0`;
        await sql`ALTER TABLE budgets ADD COLUMN IF NOT EXISTS pace_alerted BOOLEAN NOT NULL DEFAULT false`;

        await sql`CREATE TABLE IF NOT EXISTS recurring_transactions(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            title VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            category VARCHAR(255) NOT NULL,
            frequency VARCHAR(20) NOT NULL DEFAULT 'monthly',
            next_run DATE NOT NULL,
            is_active BOOLEAN NOT NULL DEFAULT true,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

        await sql`ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'LKR'`;
        await sql`ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;
        // Recurring rules can target a specific wallet; the materialized
        // transaction inherits it (NULL = the default wallet bucket).
        await sql`ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS wallet_id INTEGER`;
        // Day-before reminder dedupe: last date we pushed an "upcoming" reminder.
        await sql`ALTER TABLE recurring_transactions ADD COLUMN IF NOT EXISTS last_reminded_on DATE`;

        // Subscriptions the user dismissed from the "Detected subscriptions"
        // list, keyed by the detector's normalized series key so they stay
        // hidden across re-detections.
        await sql`CREATE TABLE IF NOT EXISTS dismissed_subscriptions(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            series_key VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE UNIQUE INDEX IF NOT EXISTS uq_dismissed_sub ON dismissed_subscriptions(user_id, series_key)`;

        await sql`CREATE TABLE IF NOT EXISTS reminders(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            title VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            category VARCHAR(255) NOT NULL,
            due_date DATE NOT NULL,
            remind_days_before INTEGER NOT NULL DEFAULT 1,
            is_active BOOLEAN NOT NULL DEFAULT true,
            last_notified_on DATE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

        await sql`ALTER TABLE reminders ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'LKR'`;
        await sql`ALTER TABLE reminders ADD COLUMN IF NOT EXISTS remind_days_before INTEGER NOT NULL DEFAULT 1`;
        await sql`ALTER TABLE reminders ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true`;
        await sql`ALTER TABLE reminders ADD COLUMN IF NOT EXISTS last_notified_on DATE`;
        await sql`ALTER TABLE reminders ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;
        await sql`CREATE INDEX IF NOT EXISTS idx_reminders_user_id ON reminders(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_reminders_due_date ON reminders(due_date)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_reminders_user_active_due ON reminders(user_id, is_active, due_date)`;

        // Savings Goals
        await sql`CREATE TABLE IF NOT EXISTS goals(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            target_amount DECIMAL(10,2) NOT NULL,
            current_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            deadline DATE,
            is_completed BOOLEAN NOT NULL DEFAULT false,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS is_completed BOOLEAN NOT NULL DEFAULT false`;
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP`;

        // ── GOAL CONTRIBUTION HISTORY ─────────────────────────────────────────
        // Every deposit/withdrawal to a goal, with its origin. Powers the goal
        // timeline, withdraw/undo, milestones, auto-contribute and round-ups.
        await sql`CREATE TABLE IF NOT EXISTS goal_contributions(
            id SERIAL PRIMARY KEY,
            goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
            user_id VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            source VARCHAR(20) NOT NULL DEFAULT 'manual',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_goal_contributions_goal ON goal_contributions(goal_id)`;
        // Highest 25/50/75 milestone already celebrated (so each fires once).
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS last_milestone INT NOT NULL DEFAULT 0`;
        // Auto-contribution rule: add auto_amount every month on auto_day (1–28).
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS auto_amount DECIMAL(10,2)`;
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS auto_day INT`;
        // Round-up savings: expenses round up to roundup_to; the spare change
        // auto-contributes to roundup_goal_id.
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS roundup_goal_id INT`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS roundup_to INT`;
        // Shared group goals: a goal linked to a group is visible to (and can
        // receive contributions from) every member.
        await sql`ALTER TABLE goals ADD COLUMN IF NOT EXISTS group_id INT`;
        await sql`CREATE INDEX IF NOT EXISTS idx_goals_group ON goals(group_id)`;

        // ── 1:1 IOUs / DEBTS ──────────────────────────────────────────────────
        // Lightweight person-to-person debt tracking ("Alex owes me 2000")
        // without the weight of a full shared group. client_op_id gives the
        // offline outbox exactly-once creates, like transactions.
        await sql`CREATE TABLE IF NOT EXISTS debts(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            counterparty_name VARCHAR(120) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            direction VARCHAR(20) NOT NULL DEFAULT 'owed_to_me',
            note TEXT,
            status VARCHAR(20) NOT NULL DEFAULT 'open',
            client_op_id VARCHAR(64),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            settled_at TIMESTAMP,
            deleted_at TIMESTAMP
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_debts_user ON debts(user_id)`;
        await sql`CREATE UNIQUE INDEX IF NOT EXISTS uq_debts_user_op ON debts(user_id, client_op_id) WHERE client_op_id IS NOT NULL`;

        // Transaction Receipts
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS receipt_url TEXT`;

        // ── WALLET TRANSFERS ──────────────────────────────────────────────────
        // A transfer is a pair of transactions (−from / +to) sharing one uuid.
        // Legs shift wallet balances but are excluded from income/expense
        // analytics, the digest and the heatmap (money only moved, not spent).
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS transfer_id VARCHAR(36)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transactions_transfer ON transactions(transfer_id) WHERE transfer_id IS NOT NULL`;

        // ── GDPR GRACE-PERIOD DELETION ────────────────────────────────────────
        // Account deletion is a 7-day soft-delete: the timestamp marks the
        // request; a daily purge job hard-deletes once the grace period lapses.
        // Signing in during the window lets the user cancel (restore).
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMP`;

        // Optional overall monthly spending cap (NULL = off), separate from the
        // per-category budgets. Measured in the user's preferred currency.
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS total_budget DECIMAL(12,2)`;

        // ── TOTP 2FA ──────────────────────────────────────────────────────────
        // totp_secret is stored on enroll but 2FA only enforces once the user
        // has proven a working authenticator (totp_enabled = true). Recovery
        // codes are stored as a JSON array of sha256 hashes; each is one-shot.
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret TEXT`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT false`;
        await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_recovery_codes TEXT`;

        // ── NOTIFICATION HISTORY TABLE ─────────────────────────────────────────
        // Stores every push/in-app notification per user so they can see a history
        // inbox like Facebook / Instagram — survives app restarts
        await sql`CREATE TABLE IF NOT EXISTS notifications(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            title TEXT NOT NULL,
            body TEXT DEFAULT '',
            type VARCHAR(50) DEFAULT 'general',
            data JSONB DEFAULT '{}',
            read BOOLEAN DEFAULT false,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, read)`;

        // ── NOTIFICATION PREFERENCES ──────────────────────────────────────────
        // One row per user. Missing row ⇒ everything enabled (see NotificationPreferenceModel).
        // Push/scheduler code consults these before delivering, so users can mute
        // categories (bill reminders, goal reminders, budget alerts, recurring runs)
        // without disabling their whole account.
        await sql`CREATE TABLE IF NOT EXISTS notification_preferences(
            user_id VARCHAR(255) PRIMARY KEY,
            push_enabled BOOLEAN NOT NULL DEFAULT true,
            bill_reminders BOOLEAN NOT NULL DEFAULT true,
            goal_reminders BOOLEAN NOT NULL DEFAULT true,
            budget_alerts BOOLEAN NOT NULL DEFAULT true,
            recurring_alerts BOOLEAN NOT NULL DEFAULT true,
            summary_digest BOOLEAN NOT NULL DEFAULT true,
            group_activity BOOLEAN NOT NULL DEFAULT true,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS summary_digest BOOLEAN NOT NULL DEFAULT true`;
        await sql`ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS group_activity BOOLEAN NOT NULL DEFAULT true`;

        // ── USER FEEDBACK / "REPORT A PROBLEM" ────────────────────────────────
        await sql`CREATE TABLE IF NOT EXISTS feedback(
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) NOT NULL,
            category VARCHAR(40) NOT NULL DEFAULT 'problem',
            subject VARCHAR(200) NOT NULL,
            message TEXT NOT NULL,
            email VARCHAR(255),
            app_version VARCHAR(40),
            platform VARCHAR(40),
            status VARCHAR(20) NOT NULL DEFAULT 'open',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_feedback_user_id ON feedback(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback(created_at DESC)`;

        // ── SHARED / FAMILY GROUPS ─────────────────────────────────────────────
        // A group is a shared "household" whose members can see a combined,
        // read-only view of everyone's transactions + a merged summary. Members
        // keep owning their own transactions (no ownership refactor); the group
        // only aggregates them. Joining is via a short invite code.
        await sql`CREATE TABLE IF NOT EXISTS groups(
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            owner_id VARCHAR(255) NOT NULL,
            invite_code VARCHAR(16) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE TABLE IF NOT EXISTS group_members(
            id SERIAL PRIMARY KEY,
            group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            user_id VARCHAR(255) NOT NULL,
            role VARCHAR(20) NOT NULL DEFAULT 'member',
            joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(group_id, user_id)
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id)`;
        await sql`CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)`;

        // ── GROUP SETTLEMENTS (Splitwise-lite) ────────────────────────────────
        // transactions.group_id marks an expense as SHARED with a group (split
        // equally between members for balance math). group_settlements records
        // member-to-member repayments so balances converge to zero.
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS group_id INTEGER`;
        await sql`CREATE INDEX IF NOT EXISTS idx_transactions_group ON transactions(group_id)`;
        await sql`CREATE TABLE IF NOT EXISTS group_settlements(
            id SERIAL PRIMARY KEY,
            group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            from_user VARCHAR(255) NOT NULL,
            to_user VARCHAR(255) NOT NULL,
            amount DECIMAL(10,2) NOT NULL,
            currency VARCHAR(10) NOT NULL DEFAULT 'LKR',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;
        await sql`CREATE INDEX IF NOT EXISTS idx_group_settlements_group ON group_settlements(group_id)`;
}
