import { UserModel } from '../models/UserModel';
import bcrypt from 'bcrypt';
import { BCRYPT_ROUNDS } from '../config/security';
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
import { csvCell } from '../utils/financeMath';
import cloudinary from '../config/cloudinary';

const DATA_EXPORT_LIMIT = 5000;

/**
 * Renders one entity list as a titled CSV section: a `## name` line, a header
 * row from the given columns, then one row per record.
 */
function csvSection(name: string, rows: any[], columns: string[]): string {
  const lines = [`## ${name}`, columns.map(csvCell).join(',')];
  for (const row of rows) {
    lines.push(
      columns
        .map((c) => {
          const v = (row as any)[c];
          if (v instanceof Date) return csvCell(v.toISOString());
          if (Array.isArray(v)) return csvCell(v.join(' '));
          return csvCell(v);
        })
        .join(','),
    );
  }
  return lines.join('\r\n');
}

/**
 * Full-account backup for the signed-in user (soft-deleted rows excluded).
 * Default JSON; `?format=csv` returns a single CSV bundle with one titled
 * section per entity (GDPR-portable, opens in any spreadsheet).
 */
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

  if (String(req.query.format || '').toLowerCase() === 'csv') {
    const sections = [
      csvSection('Transactions', transactions, ['id', 'title', 'amount', 'category', 'currency', 'created_at', 'notes', 'tags']),
      csvSection('Categories', categories, ['id', 'name', 'type']),
      csvSection('Budgets', budgets, ['id', 'category', 'amount', 'currency', 'period']),
      csvSection('Goals', goals, ['id', 'name', 'target_amount', 'current_amount', 'currency', 'deadline', 'is_completed']),
      csvSection('Reminders', reminders, ['id', 'title', 'amount', 'currency', 'due_date', 'is_active']),
      csvSection('Recurring', recurring, ['id', 'title', 'amount', 'currency', 'frequency', 'next_run']),
    ];
    // UTF-8 BOM so Excel opens non-ASCII (e.g. රු, ₹) correctly.
    const csv = '﻿' + sections.join('\r\n\r\n');
    const filename = `pulsespend_data_${new Date().toISOString().slice(0, 10)}.csv`;
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    return res.status(200).send(csv);
  }

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
  let { name, profile_photo, theme, currency, date_format, language, first_name, surname, date_of_birth, gender, contact_no, biometric_enabled } = req.body;
  const userId = String(req.user!.id);

  try {
    if (profile_photo && typeof profile_photo === 'string' && profile_photo.startsWith('data:image/')) {
      const uploadResponse = await cloudinary.uploader.upload(profile_photo, {
        folder: 'pulsespend/profiles',
        public_id: `user_${userId}`,
        overwrite: true,
      });
      profile_photo = uploadResponse.secure_url;
    }
  } catch (error) {
    console.error('Cloudinary upload error:', error);
    return res.status(500).json({ message: 'Failed to upload profile photo' });
  }

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

  const hashedPassword = await bcrypt.hash(String(newPassword), BCRYPT_ROUNDS);
  await UserModel.updatePassword(userId, hashedPassword);
  await UserModel.incrementTokenVersion(userId);

  emitToUser(userId, 'profile:password:updated', { message: 'Password updated successfully' });
  await sendPushToUser(userId, 'Password updated', 'Your password was changed successfully', { type: 'profile:password:updated' });

  return res.status(200).json({ message: 'Password updated successfully' });
}

/**
 * PUT /api/profile/:user_id/roundup — configure round-up savings.
 * Body: { goal_id, round_to } — nulls (or goal_id 0) turn the feature off.
 */
export async function updateRoundup(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { goal_id, round_to } = req.body ?? {};

  const goalId = Number(goal_id);
  const roundTo = Number(round_to);
  const enabled = Number.isInteger(goalId) && goalId > 0 && Number.isInteger(roundTo) && roundTo > 0;

  if (enabled && roundTo > 100000) {
    return res.status(400).json({ message: 'round_to is too large' });
  }

  const { sql } = await import('../config/db');
  await sql`
    UPDATE users
    SET roundup_goal_id = ${enabled ? goalId : null}, roundup_to = ${enabled ? roundTo : null}
    WHERE id = ${userId}
  `;
  return res.json({
    message: enabled ? 'Round-up savings enabled' : 'Round-up savings disabled',
    roundup_goal_id: enabled ? goalId : null,
    roundup_to: enabled ? roundTo : null,
  });
}

/**
 * GDPR deletion with a 7-day grace period: re-confirms the password, marks the
 * account for deletion, and revokes every session (token_version bump). The
 * daily purge job (accountPurgeScheduler) hard-deletes once the window lapses;
 * signing back in before then offers a restore (see cancelDeletion).
 */
export async function deleteAccount(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { password } = req.body ?? {};

  const user = await UserModel.findById(userId);
  if (!user) {
    return res.status(404).json({ message: 'User not found' });
  }

  if (!password) {
    return res.status(400).json({ message: 'Password is required to delete your account' });
  }

  const isMatch = await bcrypt.compare(String(password), user.password);
  if (!isMatch) {
    return res.status(401).json({ message: 'Password is incorrect' });
  }

  await UserModel.requestDeletion(userId);
  // Sign the account out everywhere. The user can still sign in with their
  // password during the grace window — doing so surfaces the restore offer.
  await UserModel.incrementTokenVersion(userId);

  emitToUser(userId, 'account:deleted', { message: 'Account scheduled for deletion' });

  return res.status(200).json({
    message: 'Account scheduled for deletion in 7 days. Sign in again to cancel.',
    deletion_grace_days: 7,
  });
}

/** Cancels a pending deletion — offered when signing in during the grace window. */
export async function cancelDeletion(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  await UserModel.cancelDeletion(userId);
  return res.status(200).json({ message: 'Account restored — deletion cancelled' });
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
