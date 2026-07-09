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

        // Transaction Receipts
        await sql`ALTER TABLE transactions ADD COLUMN IF NOT EXISTS receipt_url TEXT`;

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
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`;

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
}
