import express from 'express';
import { sendGroupMessage, getGroupMessages } from '../controllers/chatController';
import { requireAuth } from '../middleware/requireAuth';
import { requireGroupMember } from '../middleware/requireGroupMember';
import { validateNumericParam } from '../middleware/validators';
import { asyncHandler } from '../middleware/asyncHandler';

// These routes are mounted under /api/groups/:id/messages
// We need { mergeParams: true } so we can access the :id from the parent router
const router = express.Router({ mergeParams: true });

router.use(requireAuth);
// Every other group route checks membership inline; this sub-router did not,
// which left the whole chat readable and writable by any signed-in user who
// guessed a group id. The guard runs after the numeric-param validation so a
// junk id is a 400, not a 403.
router.use(validateNumericParam('id'), requireGroupMember('id'));

router.post('/', asyncHandler(sendGroupMessage));
router.get('/', asyncHandler(getGroupMessages));

export default router;
