import { Request, Response } from 'express';
import { AnalyticsModel } from '../models/AnalyticsModel';

export const getAnalytics = async (req: Request, res: Response) => {
  try {
    const period = (req.query.period as string) || 'week';
    const userId = String((req as any).user!.id);

    const data = await AnalyticsModel.getSummary(userId, period);

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    // Log the detail server-side, but never leak internal/DB error text to the client.
    console.error('Error fetching analytics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch analytics',
    });
  }
};

/** GET /api/analytics/digest?range=week|month — compact recap for the in-app card. */
export const getDigest = async (req: Request, res: Response) => {
  try {
    const range = req.query.range === 'month' ? 'month' : 'week';
    const userId = String((req as any).user!.id);
    const data = await AnalyticsModel.getDigest(userId, range);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching digest:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch digest' });
  }
};

/** GET /api/analytics/daily?year&month — per-day totals for the spending heatmap. */
export const getDaily = async (req: Request, res: Response) => {
  try {
    const userId = String((req as any).user!.id);
    const now = new Date();
    const year = Number(req.query.year) || now.getFullYear();
    const month = Number(req.query.month) || now.getMonth() + 1;
    if (year < 2000 || year > 2100 || month < 1 || month > 12) {
      return res.status(400).json({ success: false, message: 'Invalid year/month' });
    }
    const data = await AnalyticsModel.getDaily(userId, year, month);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching daily analytics:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch daily analytics' });
  }
};

/** GET /api/analytics/insights — templated natural-language spending insights. */
export const getInsights = async (req: Request, res: Response) => {
  try {
    const userId = String((req as any).user!.id);
    const data = await AnalyticsModel.getInsights(userId);
    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching insights:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch insights' });
  }
};
