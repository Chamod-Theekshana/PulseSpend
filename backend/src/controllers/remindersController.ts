import type { Response } from 'express';
import { ReminderModel } from '../models/ReminderModel';
import type { AuthedRequest } from '../middleware/requireAuth';
import { emitToUser } from '../socket';

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

function isValidDateString(value: string): boolean {
  if (!DATE_REGEX.test(value)) return false;
  const d = new Date(value);
  return !Number.isNaN(d.getTime());
}

export async function listReminders(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [rows, total] = await Promise.all([
    ReminderModel.listByUser(userId, limit, offset),
    ReminderModel.countByUser(userId),
  ]);
  return res.json({ reminders: rows, page: { limit, offset, total } });
}

export async function createReminder(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const {
    title,
    amount,
    category,
    due_date,
    remind_days_before,
    currency,
    is_active,
  } = req.body || {};

  if (!title || typeof title !== 'string' || title.trim().length < 1) {
    return res.status(400).json({ message: 'Title is required' });
  }
  if (title.trim().length > 200) {
    return res.status(400).json({ message: 'Title must be 200 characters or fewer' });
  }

  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }

  const cat = typeof category === 'string' && category.trim().length > 0 ? category.trim() : 'Bills';

  const dueDate = String(due_date || '').trim();
  if (!isValidDateString(dueDate)) {
    return res.status(400).json({ message: 'due_date must be a valid YYYY-MM-DD date' });
  }

  const remindDays = remind_days_before === undefined ? 1 : Number(remind_days_before);
  if (!Number.isInteger(remindDays) || remindDays < 0 || remindDays > 30) {
    return res.status(400).json({ message: 'remind_days_before must be an integer between 0 and 30' });
  }

  const cur = typeof currency === 'string' && currency.trim().length > 0 ? currency.trim().toUpperCase() : 'LKR';
  const active = is_active === undefined ? true : Boolean(is_active);

  const row = await ReminderModel.create(
    userId,
    title.trim(),
    numAmount,
    cat,
    dueDate,
    remindDays,
    cur,
    active,
  );

  emitToUser(userId, 'reminder:created', {
    title: 'Bill reminder created',
    body: `${row.title} due on ${row.due_date}`,
    reminder: row,
  });

  return res.status(201).json({ reminder: row });
}

export async function updateReminder(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const fields: {
    title?: string;
    amount?: number;
    currency?: string;
    category?: string;
    due_date?: string;
    remind_days_before?: number;
    is_active?: boolean;
  } = {};

  const {
    title,
    amount,
    currency,
    category,
    due_date,
    remind_days_before,
    is_active,
  } = req.body || {};

  if (title !== undefined) {
    if (typeof title !== 'string' || title.trim().length < 1) {
      return res.status(400).json({ message: 'Title must be a non-empty string' });
    }
    if (title.trim().length > 200) {
      return res.status(400).json({ message: 'Title must be 200 characters or fewer' });
    }
    fields.title = title.trim();
  }

  if (amount !== undefined) {
    const numAmount = Number(amount);
    if (!Number.isFinite(numAmount) || numAmount <= 0) {
      return res.status(400).json({ message: 'Amount must be a positive number' });
    }
    fields.amount = numAmount;
  }

  if (currency !== undefined) {
    if (typeof currency !== 'string' || currency.trim().length < 3 || currency.trim().length > 10) {
      return res.status(400).json({ message: 'currency must be between 3 and 10 characters' });
    }
    fields.currency = currency.trim().toUpperCase();
  }

  if (category !== undefined) {
    if (typeof category !== 'string' || category.trim().length < 1) {
      return res.status(400).json({ message: 'Category must be a non-empty string' });
    }
    fields.category = category.trim();
  }

  if (due_date !== undefined) {
    const dueDate = String(due_date).trim();
    if (!isValidDateString(dueDate)) {
      return res.status(400).json({ message: 'due_date must be a valid YYYY-MM-DD date' });
    }
    fields.due_date = dueDate;
  }

  if (remind_days_before !== undefined) {
    const remindDays = Number(remind_days_before);
    if (!Number.isInteger(remindDays) || remindDays < 0 || remindDays > 30) {
      return res.status(400).json({ message: 'remind_days_before must be an integer between 0 and 30' });
    }
    fields.remind_days_before = remindDays;
  }

  if (is_active !== undefined) {
    fields.is_active = Boolean(is_active);
  }

  if (Object.keys(fields).length === 0) {
    return res.status(400).json({ message: 'At least one field must be provided' });
  }

  const row = await ReminderModel.update(userId, id, fields);
  if (!row) {
    return res.status(404).json({ message: 'Reminder not found' });
  }

  emitToUser(userId, 'reminder:updated', {
    title: 'Bill reminder updated',
    body: `${row.title} due on ${row.due_date}`,
    reminder: row,
  });

  return res.json({ reminder: row });
}

export async function deleteReminder(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const existing = await ReminderModel.findById(userId, id);
  const ok = await ReminderModel.delete(userId, id);
  if (!ok) {
    return res.status(404).json({ message: 'Reminder not found' });
  }

  emitToUser(userId, 'reminder:deleted', {
    title: 'Bill reminder deleted',
    body: existing?.title ? `${existing.title} reminder removed` : 'Reminder removed',
    id,
  });

  return res.json({ message: 'Reminder deleted successfully' });
}

export async function bulkDeleteReminders(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await ReminderModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Reminders deleted', deletedCount });
}
