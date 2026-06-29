import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { parsePagination, validateIdListBody, validateNumericParam } from '../middleware/validators';
import {
  bulkDeleteReminders,
  createReminder,
  deleteReminder,
  listReminders,
  updateReminder,
} from '../controllers/remindersController';

const router = express.Router();

router.use(requireAuth);

router.get('/', parsePagination(), asyncHandler(listReminders));
router.post('/bulk-delete', validateIdListBody('ids'), asyncHandler(bulkDeleteReminders));
router.post('/', asyncHandler(createReminder));
router.put('/:id', validateNumericParam('id'), asyncHandler(updateReminder));
router.delete('/:id', validateNumericParam('id'), asyncHandler(deleteReminder));

export default router;
