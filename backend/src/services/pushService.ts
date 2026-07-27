import admin from 'firebase-admin';
import { sql } from '../config/db';
import * as fs from 'fs';
import * as path from 'path';
import { NotificationPreferenceModel } from '../models/NotificationPreferenceModel';
import { emitToUser } from '../socket';

let initAttempted = false;
let enabled = false;
let disabledReason: string | null = null;

function initFirebaseOnce() {
  if (initAttempted) return;
  initAttempted = true;

  try {
    if (admin.apps.length) {
      enabled = true;
      console.log('[Push Backend] Firebase already initialized');
      return;
    }

    // Option 1: JSON string in env FIREBASE_SERVICE_ACCOUNT_JSON
    const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (json && json.trim().length > 0) {
      const serviceAccount = JSON.parse(json);
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      enabled = true;
      console.log('[Push Backend] Firebase initialized from FIREBASE_SERVICE_ACCOUNT_JSON');
      return;
    }

    // Option 2: Path to service account file via GOOGLE_APPLICATION_CREDENTIALS
    const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (credPath) {
      const resolvedPath = path.resolve(credPath);
      if (!fs.existsSync(resolvedPath)) {
        throw new Error(`Service account file not found: ${resolvedPath}`);
      }
      const serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
      enabled = true;
      console.log('[Push Backend] Firebase initialized from', resolvedPath);
      return;
    }

    throw new Error(
      'No Firebase credentials found. Set FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS'
    );
  } catch (err: any) {
    enabled = false;
    disabledReason = err?.message || 'Firebase init failed';
    console.error('[Push Backend] Firebase init FAILED:', disabledReason);
  }
}

export function isPushEnabled() {
  initFirebaseOnce();
  return enabled;
}

export function getPushDisabledReason() {
  initFirebaseOnce();
  return disabledReason;
}

// ── Token management ─────────────────────────────────────────────────────────

export async function saveUserToken(userId: string | number, token: string) {
  const uid = String(userId);
  const t   = String(token);
  if (!uid || !t) return;

  await sql`
    INSERT INTO user_fcm_tokens (user_id, token)
    VALUES (${uid}, ${t})
    ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id
  `;
}

async function getUserTokens(userId: string | number): Promise<string[]> {
  const uid  = String(userId);
  const rows = await sql`SELECT token FROM user_fcm_tokens WHERE user_id = ${uid}`;
  return rows.map((r: any) => r.token).filter(Boolean);
}

async function removeTokens(tokens: string[]) {
  if (!tokens.length) return;
  await sql`DELETE FROM user_fcm_tokens WHERE token = ANY(${tokens}::text[])`;
}

// ── Notification history persistence ─────────────────────────────────────────
// Every notification (push OR in-app) is stored in the `notifications` table
// so the user can open the inbox and see their full history — like FB / IG.

export async function saveNotificationRecord(
  userId: string | number,
  title: string,
  body: string,
  type = 'general',
  data?: Record<string, string>
) {
  const uid = String(userId);
  try {
    await sql`
      INSERT INTO notifications (user_id, title, body, type, data)
      VALUES (
        ${uid},
        ${title},
        ${body},
        ${type},
        ${JSON.stringify(data ?? {})}
      )
    `;
  } catch (err) {
    // Non-fatal: log but don't crash the push flow
    console.error('[Push Backend] Failed to persist notification record:', err);
  }
}

// ── Send push to a user ───────────────────────────────────────────────────────

export async function sendPushToUser(
  userId: string | number,
  title: string,
  body: string,
  data?: Record<string, string>
) {
  console.log('[Push Backend] sendPushToUser — userId:', userId, 'title:', title);

  // 0. Respect the user's notification preferences. A muted category is
  //    dropped entirely (no inbox record, no push).
  const type = data?.type ?? 'general';
  const allowed = await NotificationPreferenceModel.isAllowed(String(userId), type);
  if (!allowed) {
    console.log('[Push Backend] Skipped — user', userId, 'has muted type:', type);
    return;
  }

  // 1. Always persist to notification history (works even without Firebase)
  await saveNotificationRecord(userId, title, body, type, data);

  // 1b. Nudge any connected client to refresh its inbox + bell badge instantly.
  //     This is the in-app channel and works with or without FCM — so even
  //     without push set up, notifications appear live while the app is open.
  emitToUser(String(userId), 'notification:new', { title, body, type });

  // 2. Send FCM push if Firebase is configured
  initFirebaseOnce();
  if (!enabled) {
    console.warn('[Push Backend] Push disabled (reason:', disabledReason, ') — notification saved to DB only');
    return;
  }

  const tokens = await getUserTokens(userId);
  if (!tokens.length) {
    console.warn('[Push Backend] No FCM tokens for user', userId, '— skipping FCM send');
    return;
  }

  try {
    const msg: admin.messaging.MulticastMessage = {
      tokens,
      // A `notification` block lets FCM display the banner automatically in the
      // background / when the app is killed. `data` is kept too so the app can
      // handle it in the foreground and deep-link on tap.
      notification: { title, body },
      data: { title, body, ...(data ?? {}) },
      android: { priority: 'high' as const, notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    };

    const resp = await admin.messaging().sendEachForMulticast(msg);
    console.log('[Push Backend] FCM response — success:', resp.successCount, 'failure:', resp.failureCount);

    // Clean up stale / invalid tokens
    const invalid: string[] = [];
    resp.responses.forEach((r: any, idx: number) => {
      if (!r.success) {
        const code = String((r.error as any)?.code || '');
        if (
          code.includes('registration-token-not-registered') ||
          code.includes('invalid-argument')
        ) {
          invalid.push(tokens[idx]);
        }
      }
    });
    if (invalid.length) await removeTokens(invalid);
  } catch (err) {
    console.error('[Push Backend] sendEachForMulticast FAILED:', err);
  }
}
