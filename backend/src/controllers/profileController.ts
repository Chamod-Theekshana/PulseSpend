import { UserModel } from '../models/UserModel';
import bcrypt from 'bcrypt';
import { emitToUser } from '../socket';
import { sendPushToUser } from '../services/pushService';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';
import { TransactionModel } from '../models/TransactionModel';
import { CategoryModel } from '../models/CategoryModel';
import { BudgetModel } from '../models/BudgetModel';
import { GoalModel } from '../models/GoalModel';
import { ReminderModel } from '../models/ReminderModel';
import { RecurringModel } from '../models/RecurringModel';

const DATA_EXPORT_LIMIT = 5000;

/** JSON backup for the signed-in user (soft-deleted rows excluded). */
export async function exportUserData(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const limit = DATA_EXPORT_LIMIT;
  const offset = 0;

  const [
    transactions,
    categories,
    budgets,
    goals,
    reminders,
    recurring,
  ] = await Promise.all([
    TransactionModel.listByUser(userId, limit, offset),
    CategoryModel.listByUser(userId, limit, offset),
    BudgetModel.listByUser(userId, limit, offset),
    GoalModel.listByUser(userId, limit, offset),
    ReminderModel.listByUser(userId, limit, offset),
    RecurringModel.listByUser(userId, limit, offset),
  ]);

  return res.status(200).json({
    exported_at: new Date().toISOString(),
    schema_version: 1,
    user_id: userId,
    transactions,
    categories,
    budgets,
    goals,
    reminders,
    recurring,
    note:
      'Transactions and lists are capped per export; restore by re-importing via API or support tools.',
  });
}

export async function getProfile(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const user = await UserModel.findById(userId);
  if (!user) {
    return res.status(404).json({ message: 'User not found' });
  }

  const { password, ...profile } = user;
  return res.status(200).json({ profile });
}

export async function updateProfile(req: AuthedRequest, res: Response) {
  const { name, profile_photo, theme, currency, date_format, language, first_name, surname, date_of_birth, gender, contact_no, biometric_enabled } = req.body;
  const userId = String(req.user!.id);

  const user = await UserModel.updateProfile(userId, {
    name,
    profile_photo,
    theme,
    currency,
    date_format,
    language,
    first_name,
    surname,
    date_of_birth,
    gender,
    contact_no,
    biometric_enabled,
  });
  const { password, ...profile } = user;

  emitToUser(userId, 'profile:updated', { profile });

  return res.status(200).json({ message: 'Profile updated', profile });
}

export async function updatePassword(req: AuthedRequest, res: Response) {
  const { currentPassword, newPassword } = req.body ?? {};
  const userId = String(req.user!.id);

  if (!currentPassword || !newPassword) {
    return res.status(400).json({ message: 'Current password and new password are required' });
  }

  if (String(newPassword).length < 8) {
    return res.status(400).json({ message: 'New password must be at least 8 characters' });
  }

  const user = await UserModel.findById(userId);
  if (!user) {
    return res.status(404).json({ message: 'User not found' });
  }

  const isMatch = await bcrypt.compare(String(currentPassword), user.password);
  if (!isMatch) {
    return res.status(401).json({ message: 'Current password is incorrect' });
  }

  const hashedPassword = await bcrypt.hash(String(newPassword), 12);
  await UserModel.updatePassword(userId, hashedPassword);
  await UserModel.incrementTokenVersion(userId);

  emitToUser(userId, 'profile:password:updated', { message: 'Password updated successfully' });
  await sendPushToUser(userId, 'Password updated', 'Your password was changed successfully', { type: 'profile:password:updated' });

  return res.status(200).json({ message: 'Password updated successfully' });
}

export async function importUserData(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const data = req.body;

  if (!data || data.user_id !== userId) {
    return res.status(400).json({ message: 'Invalid export file or user mismatch' });
  }

  try {
    if (Array.isArray(data.categories)) {
      for (const cat of data.categories) {
        try { await CategoryModel.create(userId, cat.name, cat.type); } catch(e) {}
      }
    }
    
    if (Array.isArray(data.budgets)) {
      for (const bud of data.budgets) {
        try { await BudgetModel.create(userId, bud.category, bud.amount, bud.currency, bud.period); } catch(e) {}
      }
    }
    
    if (Array.isArray(data.transactions)) {
      for (const tx of data.transactions) {
        try { await TransactionModel.create(userId, tx.title, tx.amount, tx.category, tx.created_at, tx.currency, tx.receipt_url, [], tx.notes, tx.tags); } catch(e) {}
      }
    }

    if (Array.isArray(data.goals)) {
      for (const g of data.goals) {
        try { await GoalModel.create(userId, g.name, g.target_amount, g.currency, g.deadline); } catch(e) {}
      }
    }

    if (Array.isArray(data.reminders)) {
      for (const r of data.reminders) {
        try { await ReminderModel.create(userId, r.title, r.amount, r.category, r.due_date, r.remind_days_before, r.currency, r.is_active ?? true); } catch(e) {}
      }
    }

    if (Array.isArray(data.recurring)) {
      for (const r of data.recurring) {
        try { await RecurringModel.create(userId, r.title, r.amount, r.category, r.frequency, r.next_run); } catch(e) {}
      }
    }

    return res.status(200).json({ message: 'Data imported successfully' });
  } catch (error) {
    console.error('Import error:', error);
    return res.status(500).json({ message: 'Failed to import data' });
  }
}
