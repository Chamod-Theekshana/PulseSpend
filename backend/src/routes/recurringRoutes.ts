import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { parsePagination, validateIdListBody, validateRecurringBody, validateRecurringUpdateBody } from '../middleware/validators';
import {
  listRecurring,
  listDetectedSubscriptions,
  dismissDetectedSubscription,
  createRecurring,
  updateRecurring,
  deleteRecurring,
  bulkDeleteRecurring,
} from '../controllers/recurringController';

const router = express.Router();

router.use(requireAuth);

router.get('/', parsePagination(), asyncHandler(listRecurring));
router.get('/detected', asyncHandler(listDetectedSubscriptions));
router.post('/detected/dismiss', asyncHandler(dismissDetectedSubscription));
router.post('/bulk-delete', validateIdListBody('ids'), asyncHandler(bulkDeleteRecurring));
router.post('/', validateRecurringBody, asyncHandler(createRecurring));
router.put('/:id', validateRecurringUpdateBody, asyncHandler(updateRecurring));
router.delete('/:id', asyncHandler(deleteRecurring));

export default router;
