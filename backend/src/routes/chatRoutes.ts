import express from 'express';
import { sendGroupMessage, getGroupMessages } from '../controllers/chatController';
import { requireAuth } from '../middleware/requireAuth';
import { validateNumericParam } from '../middleware/validators';
import { asyncHandler } from '../middleware/asyncHandler';

// These routes are mounted under /api/groups/:id/messages
// We need { mergeParams: true } so we can access the :id from the parent router
const router = express.Router({ mergeParams: true });

router.use(requireAuth);

router.post('/', validateNumericParam('id'), asyncHandler(sendGroupMessage));
router.get('/', validateNumericParam('id'), asyncHandler(getGroupMessages));

export default router;
