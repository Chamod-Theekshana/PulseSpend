import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';
import { sql } from '../config/db';

import { UserModel } from '../models/UserModel';
import { TransactionModel } from '../models/TransactionModel';
import { BudgetModel } from '../models/BudgetModel';
import { GoalModel } from '../models/GoalModel';
import { CategoryModel } from '../models/CategoryModel';
import { RecurringModel } from '../models/RecurringModel';
import { ReminderModel } from '../models/ReminderModel';
import { WalletModel } from '../models/WalletModel';
import { GroupModel } from '../models/GroupModel';
import { DebtModel } from '../models/DebtModel';

/**
 * GET /api/sync
 * Returns all account-scoped data in a single request. This eliminates the
 * "stampede" of 11 parallel API calls fired by the Flutter client on every
 * socket reconnect or cold start.
 */
export async function syncAll(req: AuthedRequest, res: Response) {
  try {
    const userId = String(req.user!.id);

    // Run all fetches in parallel server-side, returning them all at once.
    // The DB connection pool will handle these efficiently.
    const [
      profile,
      transactions,
      budgets,
      goals,
      categories,
      recurring,
      reminders,
      notifications,
      wallets,
      groups,
      debts,
    ] = await Promise.all([
      UserModel.findById(userId),
      TransactionModel.listByUserFiltered(userId, {}, 30, 0),
      BudgetModel.listByUser(userId, 100, 0),
      GoalModel.listByUser(userId, 100, 0),
      CategoryModel.listByUser(userId, 100, 0),
      RecurringModel.listByUser(userId, 100, 0),
      ReminderModel.listByUser(userId, 100, 0),
      
      // Inline notifications query (matches notificationsController)
      sql`
        SELECT *
        FROM notifications
        WHERE user_id = ${userId}
        ORDER BY created_at DESC
        LIMIT 50 OFFSET 0
      `,

      WalletModel.listByUser(userId),
      GroupModel.listByUser(userId),
      DebtModel.listByUser(userId),
    ]);

    return res.json({
      profile,
      transactions, // Just the first page (30 items)
      budgets,
      goals,
      categories,
      recurring,
      reminders,
      notifications,
      wallets,
      groups,
      debts,
    });
  } catch (error) {
    console.error('[Sync] Error during syncAll:', error);
    return res.status(500).json({ message: 'Internal server error during sync' });
  }
}