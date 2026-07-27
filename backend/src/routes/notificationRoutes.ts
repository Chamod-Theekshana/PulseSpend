import express from 'express';
import { saveUserToken } from '../services/pushService';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import {
  getNotificationHistory,
  markAllRead,
  markOneRead,
  clearNotifications,
  getNotificationPreferences,
  updateNotificationPreferences,
} from '../controllers/notificationsController';

const router = express.Router();

// All notification routes require auth
router.use(requireAuth);

// ── FCM Token ────────────────────────────────────────────────────────────────
// POST /api/notifications/save-token
// Called once per device after login; stores the FCM token so the backend
// can push to this device in the future.
router.post('/save-token', asyncHandler(async (req, res) => {
  const { fcm_token } = req.body ?? {};
  const user_id = String((req as any).user?.id);

  if (!user_id || !fcm_token) {
    return res.status(400).json({ message: 'fcm_token is required' });
  }

  await saveUserToken(user_id, String(fcm_token));
  return res.json({ status: 200, message: 'Token saved' });
}));

// ── Notification Inbox (Facebook / Instagram style) ──────────────────────────
// GET  /api/notifications/history        → fetch inbox list + unread count
// PATCH /api/notifications/mark-all-read → mark all as read (bell tap)
// PATCH /api/notifications/:id/read      → mark single as read
// DELETE /api/notifications/clear        → wipe inbox
router.get('/history',        asyncHandler(getNotificationHistory));
router.patch('/mark-all-read', asyncHandler(markAllRead));

// ── Notification Preferences (per-category toggles) ──────────────────────────
// GET /api/notifications/preferences  → current toggle state
// PUT /api/notifications/preferences  → update one or more toggles
router.get('/preferences', asyncHandler(getNotificationPreferences));
router.put('/preferences', asyncHandler(updateNotificationPreferences));

router.patch('/:id/read',      asyncHandler(markOneRead));
router.delete('/clear',        asyncHandler(clearNotifications));

export default router;
