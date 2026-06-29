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
  } catch (error: any) {
    console.error('Error fetching analytics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch analytics',
      error: error.message,
    });
  }
};
