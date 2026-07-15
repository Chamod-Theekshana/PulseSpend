import cron from 'node-cron';
import { UserModel } from '../models/UserModel';
import cloudinary from '../config/cloudinary';

const GRACE_DAYS = 7;

let isRunning = false;

/**
 * GDPR purge: every day at 03:30, hard-deletes accounts whose deletion request
 * has passed the 7-day grace window (see deleteAccount in profileController).
 * Signing in during the window and choosing "Restore" clears the request, so
 * anything still marked here is genuinely abandoned.
 */
export class AccountPurgeScheduler {
  static start(): void {
    console.log('[Purge] Scheduling daily account purge (03:30)');
    cron.schedule('30 3 * * *', () => {
      void AccountPurgeScheduler.run();
    });
  }

  static async run(): Promise<void> {
    if (isRunning) return;
    isRunning = true;
    try {
      const due = await UserModel.listDueForPurge(GRACE_DAYS);
      if (!due.length) return;
      console.log(`[Purge] Hard-deleting ${due.length} account(s) past the grace period`);

      for (const { id } of due) {
        try {
          // Best-effort Cloudinary cleanup before the row disappears.
          try {
            await cloudinary.uploader.destroy(`pulsespend/profiles/user_${id}`);
          } catch (err) {
            console.error('[Purge] Cloudinary cleanup failed for', id, err);
          }
          await UserModel.deleteAccount(id);
          console.log(`[Purge] Account ${id} permanently deleted`);
        } catch (err) {
          console.error('[Purge] failed for account', id, err);
        }
      }
    } catch (err) {
      console.error('[Purge] run failed:', err);
    } finally {
      isRunning = false;
    }
  }
}
