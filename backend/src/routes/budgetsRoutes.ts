import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { parsePagination, validateBudgetBody, validateBudgetUpdateBody, validateIdListBody, validateNumericParam } from '../middleware/validators';
import {
  listBudgets,
  getBudgetStatus,
  getTotalBudgetStatus,
  setTotalBudget,
  createBudget,
  updateBudget,
  deleteBudget,
  bulkDeleteBudgets,
} from '../controllers/budgetsController';

const router = express.Router();

router.use(requireAuth);

router.get('/', parsePagination(), asyncHandler(listBudgets));
router.get('/status', asyncHandler(getBudgetStatus));
router.get('/total-status', asyncHandler(getTotalBudgetStatus));
router.put('/total', asyncHandler(setTotalBudget));
router.post('/bulk-delete', validateIdListBody('ids'), asyncHandler(bulkDeleteBudgets));
router.post('/', validateBudgetBody, asyncHandler(createBudget));
router.put('/:id', validateNumericParam('id'), validateBudgetUpdateBody, asyncHandler(updateBudget));
router.delete('/:id', validateNumericParam('id'), asyncHandler(deleteBudget));

export default router;
