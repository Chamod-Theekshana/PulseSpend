import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { getAllRates, convert } from '../services/exchangeRateService';
import { asyncHandler } from '../middleware/asyncHandler';

const router = Router();

// GET /api/exchange-rates?base=USD
router.get('/', requireAuth, asyncHandler(async (req, res) => {
  try {
    const base = String(req.query.base || 'USD').toUpperCase();
    const rates = await getAllRates(base);
    return res.json({ base, rates });
  } catch (err: any) {
    console.error('[ExchangeRate] Error:', err);
    return res.status(500).json({ message: 'Failed to fetch exchange rates' });
  }
}));

// GET /api/exchange-rates/convert?from=USD&to=LKR&amount=100
router.get('/convert', requireAuth, asyncHandler(async (req, res) => {
  try {
    const from = String(req.query.from || 'USD').toUpperCase();
    const to = String(req.query.to || 'LKR').toUpperCase();
    const amount = Number(req.query.amount || 0);

    if (!Number.isFinite(amount)) {
      return res.status(400).json({ message: 'Invalid amount' });
    }

    const converted = await convert(amount, from, to);
    const rate = converted / (amount || 1);
    return res.json({ from, to, amount, converted, rate });
  } catch (err: any) {
    console.error('[ExchangeRate] Convert error:', err);
    return res.status(500).json({ message: 'Failed to convert' });
  }
}));

export default router;
