import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { parsePagination, validateGoalBody, validateGoalContributionBody, validateGoalUpdateBody, validateIdListBody, validateNumericParam } from '../middleware/validators';
import { listGoals, createGoal, updateGoal, contributeToGoal, listGoalContributions, setAutoRule, deleteGoal, bulkDeleteGoals } from '../controllers/goalsController';

const router = express.Router();
router.use(requireAuth);

router.get('/', parsePagination(), asyncHandler(listGoals));
router.post('/bulk-delete', validateIdListBody('ids'), asyncHandler(bulkDeleteGoals));
router.post('/', validateGoalBody, asyncHandler(createGoal));
router.put('/:id', validateNumericParam('id'), validateGoalUpdateBody, asyncHandler(updateGoal));
router.post('/:id/contribute', validateNumericParam('id'), validateGoalContributionBody, asyncHandler(contributeToGoal));
router.get('/:id/contributions', validateNumericParam('id'), asyncHandler(listGoalContributions));
router.put('/:id/auto', validateNumericParam('id'), asyncHandler(setAutoRule));
router.delete('/:id', validateNumericParam('id'), asyncHandler(deleteGoal));

export default router;
