import { Router } from 'express';
import { getAnalytics } from '../controllers/analyticsController';
import { requireAuth } from '../middleware/requireAuth';

const router = Router();

// Secure the route with requireAuth middleware
router.get('/', requireAuth, getAnalytics);

export default router;

