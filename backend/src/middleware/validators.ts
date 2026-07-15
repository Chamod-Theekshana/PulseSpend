import { Request, Response, NextFunction } from 'express';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const TAG_REGEX = /^[a-z0-9][a-z0-9_-]{0,29}$/i;

function isValidDateString(value: string): boolean {
  if (!DATE_REGEX.test(value)) return false;
  const d = new Date(value);
  return !Number.isNaN(d.getTime());
}

function normalizeCurrency(value: any, fallback: string = 'LKR'): string {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value !== 'string') return fallback;
  const cleaned = value.trim().toUpperCase();
  return cleaned || fallback;
}

export function requireJson(req: Request, res: Response, next: NextFunction) {
  if (
    (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH') &&
    req.headers['content-type']?.includes('application/json')
  ) {
    if (req.body == null) {
      return res.status(400).json({ message: 'Request body is required' });
    }
  }
  return next();
}

export function validateNumericParam(paramName: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const val = (req.params as any)[paramName];
    if (!val || !/^\d+$/.test(String(val))) {
      return res.status(400).json({ message: `Invalid ${paramName}` });
    }
    next();
  };
}

export function validateTransactionBody(req: Request, res: Response, next: NextFunction) {
  const { title, amount, category, created_at, dateISO, splits, notes, tags } = req.body ?? {};

  if (typeof title !== 'string' || title.trim().length < 1) {
    return res.status(400).json({ message: 'Title is required' });
  }
  if (title.trim().length > 200) {
    return res.status(400).json({ message: 'Title must be 200 characters or fewer' });
  }

  let normalizedNotes: string | undefined;
  if (notes !== undefined) {
    if (notes !== null && typeof notes !== 'string') {
      return res.status(400).json({ message: 'notes must be a string' });
    }
    const cleanedNotes = notes === null ? '' : notes.trim();
    if (cleanedNotes.length > 2000) {
      return res.status(400).json({ message: 'notes must be 2000 characters or fewer' });
    }
    normalizedNotes = cleanedNotes;
  }

  let normalizedTags: string[] | undefined;
  if (tags !== undefined) {
    if (!Array.isArray(tags)) {
      return res.status(400).json({ message: 'tags must be an array of strings' });
    }
    if (tags.length > 20) {
      return res.status(400).json({ message: 'A maximum of 20 tags is allowed' });
    }

    const seenTags = new Set<string>();
    const parsedTags: string[] = [];

    for (let i = 0; i < tags.length; i++) {
      const rawTag = tags[i];
      if (typeof rawTag !== 'string') {
        return res.status(400).json({ message: `Tag #${i + 1} must be a string` });
      }

      const cleanTag = rawTag.trim().replace(/^#+/, '').toLowerCase();
      if (!cleanTag) {
        return res.status(400).json({ message: `Tag #${i + 1} is empty` });
      }
      if (!TAG_REGEX.test(cleanTag)) {
        return res.status(400).json({
          message: `Tag #${i + 1} is invalid (use letters, numbers, _ or -; max 30 chars)`,
        });
      }

      if (!seenTags.has(cleanTag)) {
        seenTags.add(cleanTag);
        parsedTags.push(cleanTag);
      }
    }

    normalizedTags = parsedTags;
  }

  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount)) {
    return res.status(400).json({ message: 'Amount must be a number' });
  }
  if (numAmount === 0) {
    return res.status(400).json({ message: 'Amount cannot be zero' });
  }
  if (Math.abs(numAmount) > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount is too large' });
  }

  let normalizedCategory = typeof category === 'string' ? category.trim() : '';
  let normalizedSplits: Array<{ category: string; amount: number; percentage: number }> | undefined;

  if (splits !== undefined) {
    if (!Array.isArray(splits)) {
      return res.status(400).json({ message: 'splits must be an array' });
    }

    if (splits.length === 1) {
      return res.status(400).json({ message: 'Split transactions require at least 2 categories' });
    }

    if (splits.length > 0 && numAmount >= 0) {
      return res.status(400).json({ message: 'Splits are supported for expense transactions only' });
    }

    if (splits.length === 0) {
      normalizedSplits = [];
    } else {
      const absTotal = Math.abs(numAmount);
      let sumAmounts = 0;
      const seenCategories = new Set<string>();
      const parsed: Array<{ category: string; amount: number }> = [];

      for (let i = 0; i < splits.length; i++) {
        const row = (splits[i] ?? {}) as any;
        const splitCategory = typeof row.category === 'string' ? row.category.trim() : '';
        if (!splitCategory) {
          return res.status(400).json({ message: `Split #${i + 1}: category is required` });
        }
        if (splitCategory.length > 255) {
          return res.status(400).json({ message: `Split #${i + 1}: category is too long` });
        }

        const categoryKey = splitCategory.toLowerCase();
        if (seenCategories.has(categoryKey)) {
          return res.status(400).json({ message: 'Split categories must be unique' });
        }
        seenCategories.add(categoryKey);

        const splitAmount = Number(row.amount);
        if (!Number.isFinite(splitAmount) || splitAmount <= 0) {
          return res.status(400).json({ message: `Split #${i + 1}: amount must be a positive number` });
        }

        const roundedAmount = Math.round(splitAmount * 100) / 100;
        parsed.push({ category: splitCategory, amount: roundedAmount });
        sumAmounts += roundedAmount;
      }

      const roundedSum = Math.round(sumAmounts * 100) / 100;
      if (Math.abs(roundedSum - absTotal) > 0.05) {
        return res.status(400).json({
          message: 'Split amounts must add up to the total expense amount',
        });
      }

      let allocatedAmount = 0;
      let allocatedPercentage = 0;
      normalizedSplits = parsed.map((split, index) => {
        const isLast = index === parsed.length - 1;

        const amountAbs = isLast
          ? Math.round((absTotal - allocatedAmount) * 100) / 100
          : split.amount;
        const percentage = isLast
          ? Math.round((100 - allocatedPercentage) * 100) / 100
          : Math.round(((amountAbs / absTotal) * 100) * 100) / 100;

        allocatedAmount = Math.round((allocatedAmount + amountAbs) * 100) / 100;
        allocatedPercentage = Math.round((allocatedPercentage + percentage) * 100) / 100;

        return {
          category: split.category,
          amount: -Math.abs(amountAbs),
          percentage,
        };
      });

      normalizedCategory = normalizedSplits[0]?.category || normalizedCategory;
    }
  }

  if (!normalizedCategory) {
    return res.status(400).json({ message: 'Category is required' });
  }

  // Accept dateISO or created_at as YYYY-MM-DD
  const rawDate = dateISO ?? created_at;
  if (rawDate !== undefined) {
    const s = String(rawDate);
    if (!DATE_REGEX.test(s)) {
      return res.status(400).json({ message: 'Date must be in YYYY-MM-DD format' });
    }
    // Validate it's an actual calendar date
    const d = new Date(s);
    if (isNaN(d.getTime())) {
      return res.status(400).json({ message: 'Invalid date' });
    }
    (req.body as any).created_at = s;
  }

  // Normalize
  (req.body as any).title = title.trim();
  (req.body as any).category = normalizedCategory;
  (req.body as any).amount = numAmount;
  if (normalizedNotes !== undefined) {
    (req.body as any).notes = normalizedNotes;
  }
  if (normalizedTags !== undefined) {
    (req.body as any).tags = normalizedTags;
  }
  if (normalizedSplits !== undefined) {
    (req.body as any).splits = normalizedSplits;
  }

  next();
}

export const SUPPORTED_LANGUAGES = ['English', 'Sinhala', 'Tamil', 'Spanish', 'French', 'German', 'Hindi'];

export function validateProfileUpdateBody(req: Request, res: Response, next: NextFunction) {
  const { name, profile_photo, theme, currency, date_format, language, biometric_enabled, first_name, surname, date_of_birth, gender, contact_no } = req.body ?? {};

  const allowedDateFormats = new Set(['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD']);
  const allowedLanguages = new Set(SUPPORTED_LANGUAGES);

  if (name !== undefined) {
    if (typeof name !== 'string' || name.trim().length < 1) {
      return res.status(400).json({ message: 'Name must be a non-empty string' });
    }
    if (name.trim().length > 100) {
      return res.status(400).json({ message: 'Name must be 100 characters or fewer' });
    }
    (req.body as any).name = name.trim();
  }

  if (profile_photo !== undefined) {
    if (typeof profile_photo !== 'string' || profile_photo.trim().length < 1) {
      return res.status(400).json({ message: 'profile_photo must be a non-empty string' });
    }
    // Basic URL check
    try {
      new URL(profile_photo.trim());
    } catch {
      return res.status(400).json({ message: 'profile_photo must be a valid URL' });
    }
    (req.body as any).profile_photo = profile_photo.trim();
  }

  if (theme !== undefined) {
    if (theme !== 'dark' && theme !== 'light' && theme !== 'system') {
      return res.status(400).json({ message: "theme must be 'dark', 'light' or 'system'" });
    }
  }

  if (currency !== undefined) {
    if (typeof currency !== 'string' || currency.trim().length < 1) {
      return res.status(400).json({ message: 'currency must be a non-empty string' });
    }
    const cleaned = currency.trim().toUpperCase();
    if (cleaned.length < 3 || cleaned.length > 10) {
      return res.status(400).json({ message: 'currency must be between 3 and 10 characters' });
    }
    (req.body as any).currency = cleaned;
  }

  if (date_format !== undefined) {
    if (typeof date_format !== 'string' || !allowedDateFormats.has(date_format)) {
      return res.status(400).json({
        message: 'date_format must be one of: DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD',
      });
    }
  }

  if (language !== undefined) {
    if (typeof language !== 'string' || !allowedLanguages.has(language)) {
      return res.status(400).json({
        message: `language must be one of: ${SUPPORTED_LANGUAGES.join(', ')}`,
      });
    }
  }

  if (biometric_enabled !== undefined) {
    if (typeof biometric_enabled !== 'boolean') {
      return res.status(400).json({ message: 'biometric_enabled must be a boolean' });
    }
  }

  if (first_name !== undefined) {
    if (typeof first_name !== 'string' || first_name.trim().length > 100) {
      return res.status(400).json({ message: 'first_name must be 100 characters or fewer' });
    }
    (req.body as any).first_name = first_name.trim();
  }

  if (surname !== undefined) {
    if (typeof surname !== 'string' || surname.trim().length > 100) {
      return res.status(400).json({ message: 'surname must be 100 characters or fewer' });
    }
    (req.body as any).surname = surname.trim();
  }

  if (date_of_birth !== undefined) {
    if (date_of_birth !== null) {
      const s = String(date_of_birth).trim();
      // Simple date check
      if (isNaN(Date.parse(s))) {
         return res.status(400).json({ message: 'date_of_birth must be a valid date' });
      }
      (req.body as any).date_of_birth = s;
    }
  }

  if (gender !== undefined) {
    if (gender !== null && typeof gender !== 'string') {
      return res.status(400).json({ message: 'gender must be a string' });
    }
    (req.body as any).gender = gender?.trim();
  }

  if (contact_no !== undefined) {
    if (contact_no !== null && typeof contact_no !== 'string') {
      return res.status(400).json({ message: 'contact_no must be a string' });
    }
    (req.body as any).contact_no = contact_no?.trim();
  }

  if (
    name === undefined &&
    profile_photo === undefined &&
    theme === undefined &&
    currency === undefined &&
    date_format === undefined &&
    language === undefined &&
    biometric_enabled === undefined &&
    first_name === undefined &&
    surname === undefined &&
    date_of_birth === undefined &&
    gender === undefined &&
    contact_no === undefined
  ) {
    return res.status(400).json({
      message: 'At least one field is required to update',
    });
  }

  next();
}

export function validateBudgetBody(req: Request, res: Response, next: NextFunction) {
  const { category, amount, currency, period } = req.body ?? {};

  if (!category || typeof category !== 'string' || category.trim().length < 1) {
    return res.status(400).json({ message: 'Category is required' });
  }
  if (category.trim().length > 255) {
    return res.status(400).json({ message: 'Category is too long' });
  }

  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }
  if (numAmount > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount is too large' });
  }

  const p = (period || 'monthly') as string;
  if (!['weekly', 'monthly', 'yearly'].includes(p)) {
    return res.status(400).json({ message: 'Period must be one of: weekly, monthly, yearly' });
  }

  const c = normalizeCurrency(currency, 'LKR');
  if (c.length < 3 || c.length > 10) {
    return res.status(400).json({ message: 'currency must be between 3 and 10 characters' });
  }

  (req.body as any).category = category.trim();
  (req.body as any).amount = numAmount;
  (req.body as any).currency = c;
  (req.body as any).period = p;
  next();
}

export function validateBudgetUpdateBody(req: Request, res: Response, next: NextFunction) {
  const { amount } = req.body ?? {};
  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0) {
    return res.status(400).json({ message: 'Amount must be a positive number' });
  }
  if (numAmount > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount is too large' });
  }
  (req.body as any).amount = numAmount;
  next();
}

export function validateCategoryBody(req: Request, res: Response, next: NextFunction) {
  const { name, type } = req.body ?? {};
  if (!name || typeof name !== 'string' || name.trim().length < 2) {
    return res.status(400).json({ message: 'Category name is required' });
  }
  if (name.trim().length > 255) {
    return res.status(400).json({ message: 'Category name is too long' });
  }

  const t = (type || 'expense') as 'expense' | 'income' | 'both';
  if (!['expense', 'income', 'both'].includes(t)) {
    return res.status(400).json({ message: 'Invalid category type' });
  }

  (req.body as any).name = name.trim();
  (req.body as any).type = t;
  next();
}

export function validateGoalBody(req: Request, res: Response, next: NextFunction) {
  const { name, target_amount, currency, deadline } = req.body ?? {};

  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ message: 'Goal name is required' });
  }
  if (name.trim().length > 200) {
    return res.status(400).json({ message: 'Goal name must be 200 characters or fewer' });
  }

  const amount = Number(target_amount);
  if (!Number.isFinite(amount) || amount <= 0) {
    return res.status(400).json({ message: 'target_amount must be a positive number' });
  }
  if (amount > 1_000_000_000) {
    return res.status(400).json({ message: 'target_amount is too large' });
  }

  let normalizedDeadline: string | null = null;
  if (deadline) {
    const s = String(deadline).trim();
    if (!isValidDateString(s)) {
      return res.status(400).json({ message: 'deadline must be a valid YYYY-MM-DD date' });
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const d = new Date(s);
    d.setHours(0, 0, 0, 0);
    if (d.getTime() < today.getTime()) {
      return res.status(400).json({ message: 'Deadline cannot be in the past' });
    }
    normalizedDeadline = s;
  }

  const cur = normalizeCurrency(currency, 'LKR');
  if (cur.length < 3 || cur.length > 10) {
    return res.status(400).json({ message: 'currency must be between 3 and 10 characters' });
  }

  (req.body as any).name = name.trim();
  (req.body as any).target_amount = amount;
  (req.body as any).currency = cur;
  (req.body as any).deadline = normalizedDeadline;
  next();
}

export function validateGoalUpdateBody(req: Request, res: Response, next: NextFunction) {
  return validateGoalBody(req, res, next);
}

export function validateGoalContributionBody(req: Request, res: Response, next: NextFunction) {
  const { amount, currency } = req.body ?? {};
  const numAmount = Number(amount);
  // Negative = withdrawal (goal timeline supports both directions); zero is meaningless.
  if (!Number.isFinite(numAmount) || numAmount === 0 || Math.abs(numAmount) > 1_000_000_000) {
    return res.status(400).json({ message: 'amount must be a non-zero number' });
  }
  const cur = normalizeCurrency(currency, 'LKR');
  if (cur.length < 3 || cur.length > 10) {
    return res.status(400).json({ message: 'currency must be between 3 and 10 characters' });
  }
  (req.body as any).amount = numAmount;
  (req.body as any).currency = cur;
  next();
}

export function validateRecurringBody(req: Request, res: Response, next: NextFunction) {
  const { title, amount, category, frequency, startDate } = req.body ?? {};
  const VALID_FREQUENCIES = ['daily', 'weekly', 'monthly', 'yearly'];

  if (!title || typeof title !== 'string' || title.trim().length < 1) {
    return res.status(400).json({ message: 'Title is required' });
  }
  if (title.trim().length > 200) {
    return res.status(400).json({ message: 'Title must be 200 characters or fewer' });
  }

  if (!category || typeof category !== 'string' || category.trim().length < 1) {
    return res.status(400).json({ message: 'Category is required' });
  }
  if (category.trim().length > 255) {
    return res.status(400).json({ message: 'Category is too long' });
  }

  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount === 0) {
    return res.status(400).json({ message: 'Amount must be a non-zero number' });
  }
  if (Math.abs(numAmount) > 1_000_000_000) {
    return res.status(400).json({ message: 'Amount is too large' });
  }

  const freq = frequency || 'monthly';
  if (!VALID_FREQUENCIES.includes(freq)) {
    return res.status(400).json({ message: `Frequency must be one of: ${VALID_FREQUENCIES.join(', ')}` });
  }

  if (startDate !== undefined && startDate !== null && String(startDate).trim() !== '') {
    const s = String(startDate).trim();
    if (!isValidDateString(s)) {
      return res.status(400).json({ message: 'startDate must be a valid YYYY-MM-DD date' });
    }
    (req.body as any).startDate = s;
  } else {
    (req.body as any).startDate = undefined;
  }

  const { currency, wallet_id } = req.body ?? {};
  if (currency !== undefined && currency !== null && String(currency).trim() !== '') {
    const c = String(currency).trim();
    if (c.length < 2 || c.length > 10) {
      return res.status(400).json({ message: 'Currency must be 2–10 characters' });
    }
    (req.body as any).currency = c.toUpperCase();
  }
  if (wallet_id !== undefined && wallet_id !== null) {
    const w = Number(wallet_id);
    if (!Number.isInteger(w) || w < 0) {
      return res.status(400).json({ message: 'wallet_id must be a non-negative integer' });
    }
  }

  (req.body as any).title = title.trim();
  (req.body as any).category = category.trim();
  (req.body as any).amount = numAmount;
  (req.body as any).frequency = freq;
  next();
}

export function validateRecurringUpdateBody(req: Request, res: Response, next: NextFunction) {
  const { title, amount, category, frequency, is_active } = req.body ?? {};
  const VALID_FREQUENCIES = ['daily', 'weekly', 'monthly', 'yearly'];

  if (title !== undefined) {
    if (typeof title !== 'string' || title.trim().length < 1) {
      return res.status(400).json({ message: 'Title must be a non-empty string' });
    }
    if (title.trim().length > 200) {
      return res.status(400).json({ message: 'Title must be 200 characters or fewer' });
    }
    (req.body as any).title = title.trim();
  }

  if (category !== undefined) {
    if (typeof category !== 'string' || category.trim().length < 1) {
      return res.status(400).json({ message: 'Category must be a non-empty string' });
    }
    if (category.trim().length > 255) {
      return res.status(400).json({ message: 'Category is too long' });
    }
    (req.body as any).category = category.trim();
  }

  if (amount !== undefined) {
    const numAmount = Number(amount);
    if (!Number.isFinite(numAmount) || numAmount === 0) {
      return res.status(400).json({ message: 'Amount must be a non-zero number' });
    }
    if (Math.abs(numAmount) > 1_000_000_000) {
      return res.status(400).json({ message: 'Amount is too large' });
    }
    (req.body as any).amount = numAmount;
  }

  if (frequency !== undefined) {
    if (!VALID_FREQUENCIES.includes(frequency)) {
      return res.status(400).json({ message: `Frequency must be one of: ${VALID_FREQUENCIES.join(', ')}` });
    }
    (req.body as any).frequency = frequency;
  }

  if (is_active !== undefined) {
    (req.body as any).is_active = Boolean(is_active);
  }

  const { currency, wallet_id } = req.body ?? {};
  if (currency !== undefined && currency !== null && String(currency).trim() !== '') {
    const c = String(currency).trim();
    if (c.length < 2 || c.length > 10) {
      return res.status(400).json({ message: 'Currency must be 2–10 characters' });
    }
    (req.body as any).currency = c.toUpperCase();
  }
  if (wallet_id !== undefined && wallet_id !== null) {
    const w = Number(wallet_id);
    if (!Number.isInteger(w) || w < 0) {
      return res.status(400).json({ message: 'wallet_id must be a non-negative integer' });
    }
  }

  if (
    title === undefined &&
    amount === undefined &&
    category === undefined &&
    frequency === undefined &&
    is_active === undefined &&
    currency === undefined &&
    wallet_id === undefined
  ) {
    return res.status(400).json({ message: 'At least one field must be provided' });
  }

  next();
}

export function validateEmailBody(req: Request, res: Response, next: NextFunction) {
  const { email } = req.body ?? {};
  if (!email || !EMAIL_REGEX.test(String(email))) {
    return res.status(400).json({ message: 'Valid email is required' });
  }
  (req.body as any).email = String(email).toLowerCase().trim();
  next();
}

export function parsePagination(defaultLimit = 50, maxLimit = 200) {
  return (req: Request, res: Response, next: NextFunction) => {
    const rawLimit = req.query.limit ?? defaultLimit;
    const rawOffset = req.query.offset ?? 0;

    const limit = Number(rawLimit);
    const offset = Number(rawOffset);

    if (!Number.isFinite(limit) || limit < 1) {
      return res.status(400).json({ message: 'limit must be a positive number' });
    }
    if (!Number.isFinite(offset) || offset < 0) {
      return res.status(400).json({ message: 'offset must be 0 or greater' });
    }

    const normalizedLimit = Math.min(Math.floor(limit), maxLimit);
    const normalizedOffset = Math.floor(offset);

    (req as any).pagination = { limit: normalizedLimit, offset: normalizedOffset };
    next();
  };
}

/**
 * Reads the optional transaction filter params off the query string into a
 * plain object suitable for TransactionModel's filtered queries. Lenient by
 * design: anything malformed (e.g. a non-numeric amount) is simply dropped so
 * the list still returns rather than 400-ing.
 */
export function parseTransactionFilters(req: Request) {
  const q = typeof req.query.q === 'string' && req.query.q.trim() ? req.query.q.trim() : null;
  const category =
    typeof req.query.category === 'string' && req.query.category.trim()
      ? req.query.category.trim()
      : null;

  const isoDate = (v: unknown) =>
    typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
  const from = isoDate(req.query.from);
  const to = isoDate(req.query.to);

  const num = (v: unknown) => {
    const n = Number(v);
    return typeof v !== 'undefined' && v !== '' && Number.isFinite(n) ? n : null;
  };
  const minAmount = num(req.query.minAmount);
  const maxAmount = num(req.query.maxAmount);

  const rawType = typeof req.query.type === 'string' ? req.query.type.toLowerCase() : '';
  const type = rawType === 'income' || rawType === 'expense' ? (rawType as 'income' | 'expense') : null;

  // Wallet filter: a positive id, or 0 for "the default (unassigned) wallet".
  const rawWallet = Number(req.query.wallet_id);
  const walletId =
    typeof req.query.wallet_id !== 'undefined' && Number.isInteger(rawWallet) && rawWallet >= 0
      ? rawWallet
      : null;

  return { q, category, from, to, minAmount, maxAmount, type, walletId };
}

const MAX_BULK_IDS = 200;

export function validateIdListBody(field: string = 'ids') {
  return (req: Request, res: Response, next: NextFunction) => {
    const ids = (req.body as any)?.[field];
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ message: `${field} must be a non-empty array` });
    }
    if (ids.length > MAX_BULK_IDS) {
      return res.status(400).json({ message: `${field} cannot exceed ${MAX_BULK_IDS} items` });
    }
    const parsed: number[] = [];
    for (const id of ids) {
      const num = Number(id);
      if (!Number.isInteger(num) || num <= 0) {
        return res.status(400).json({ message: `${field} must contain positive integers` });
      }
      parsed.push(num);
    }
    (req.body as any)[field] = parsed;
    next();
  };
}
