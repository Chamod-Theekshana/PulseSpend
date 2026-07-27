import { Router } from 'express';
import { getAnalytics, getDaily, getDigest, getInsights } from '../controllers/analyticsController';
import { requireAuth } from '../middleware/requireAuth';

const router = Router();

// Secure the routes with requireAuth middleware
router.get('/', requireAuth, getAnalytics);
router.get('/digest', requireAuth, getDigest);
router.get('/insights', requireAuth, getInsights);
router.get('/daily', requireAuth, getDaily);

export default router;

