import { GoalModel } from '../models/GoalModel';
import { emitToUser } from '../socket';
import type { AuthedRequest } from '../middleware/requireAuth';

export async function listGoals(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [goals, total] = await Promise.all([
    GoalModel.listByUser(userId, limit, offset),
    GoalModel.countByUser(userId),
  ]);
  return res.json({ goals, page: { limit, offset, total } });
}

export async function createGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const { name, target_amount, currency, deadline } = req.body;

  const goal = await GoalModel.create(
    userId,
    name,
    Number(target_amount),
    currency || 'LKR',
    deadline || null,
  );
  return res.status(201).json({ goal });
}

export async function updateGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const { name, target_amount, currency, deadline } = req.body;

  const goal = await GoalModel.update(userId, id, name, Number(target_amount), currency || 'LKR', deadline || null);
  if (!goal) return res.status(404).json({ message: 'Not found' });
  return res.json({ goal });
}

export async function contributeToGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  const { amount, currency } = req.body;

  // Fetch the goal to know its target currency
  const existing = await GoalModel.findById(userId, id);
  if (!existing) return res.status(404).json({ message: 'Not found' });

  let contributionAmount = Number(amount);
  const fromCurrency = (currency || existing.currency || 'LKR').toUpperCase();
  const toCurrency = (existing.currency || 'LKR').toUpperCase();

  // Convert contribution to the goal's currency if they differ
  if (fromCurrency !== toCurrency) {
    try {
      const { convert } = await import('../services/exchangeRateService');
      contributionAmount = await convert(contributionAmount, fromCurrency, toCurrency);
    } catch (e) {
      console.warn(`[Goals] Currency conversion ${fromCurrency}→${toCurrency} failed, using raw amount:`, e);
      // Proceed with raw amount but flag it in the response
      const goal = await GoalModel.addContribution(userId, id, contributionAmount);
      if (!goal) return res.status(404).json({ message: 'Not found' });
      if (goal.is_completed) emitToUser(userId, 'goal:completed', { goal });
      return res.json({ goal, conversion_warning: `Rate unavailable for ${fromCurrency}→${toCurrency}. Amount recorded as-is.` });
    }
  }

  const goal = await GoalModel.addContribution(userId, id, contributionAmount);
  if (!goal) return res.status(404).json({ message: 'Not found' });

  if (goal.is_completed) {
    emitToUser(userId, 'goal:completed', { goal });
  }

  return res.json({ goal });
}

export async function deleteGoal(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);

  await GoalModel.delete(userId, id);
  return res.json({ message: 'Goal deleted successfully' });
}

export async function bulkDeleteGoals(req: AuthedRequest, res: any) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await GoalModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Goals deleted', deletedCount });
}
