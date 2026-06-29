import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { asyncHandler } from '../middleware/asyncHandler';
import { parsePagination, validateCategoryBody, validateIdListBody, validateNumericParam } from '../middleware/validators';
import {
  bulkDeleteCategories,
  createCategory,
  deleteCategory,
  listCategories,
  updateCategory,
} from '../controllers/categoriesController';

const router = express.Router();

router.use(requireAuth);

router.get('/', parsePagination(), asyncHandler(listCategories));
router.post('/bulk-delete', validateIdListBody('ids'), asyncHandler(bulkDeleteCategories));
router.post('/', validateCategoryBody, asyncHandler(createCategory));
router.put('/:id', validateNumericParam('id'), validateCategoryBody, asyncHandler(updateCategory));
router.delete('/:id', validateNumericParam('id'), asyncHandler(deleteCategory));

export default router;
