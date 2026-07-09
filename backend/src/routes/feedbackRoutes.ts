import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { submitFeedback, listMyFeedback } from '../controllers/feedbackController';

const router = express.Router();

router.use(requireAuth);

// POST /api/feedback  → submit a problem report / feedback
// GET  /api/feedback  → list the user's own submissions
router.post('/', asyncHandler(submitFeedback));
router.get('/', asyncHandler(listMyFeedback));

export default router;
