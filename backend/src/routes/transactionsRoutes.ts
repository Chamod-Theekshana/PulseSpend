import express from "express";
import {
  createTransaction,
  deleteTransaction,
  getTransactionById,
  getTransactionByUserId,
  getTransactionSummaryByUserId,
  updateTransaction,
  bulkDeleteTransactions,
} from "../controllers/transactionsController";
import { parsePagination, validateIdListBody, validateNumericParam, validateTransactionBody } from "../middleware/validators";
import { requireAuth, requireUserMatchParam } from "../middleware/requireAuth";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

// IMPORTANT: More specific routes must come first (otherwise "/:user_id" will catch them)
router.get(
  "/summary/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(getTransactionSummaryByUserId)
);

router.get(
  "/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  parsePagination(),
  asyncHandler(getTransactionByUserId)
);

router.get("/id/:id", validateNumericParam("id"), asyncHandler(getTransactionById));

router.post("/", validateTransactionBody, asyncHandler(createTransaction));

router.put("/:id", validateNumericParam("id"), validateTransactionBody, asyncHandler(updateTransaction));

router.delete("/:id", validateNumericParam("id"), asyncHandler(deleteTransaction));

router.post(
  "/bulk-delete",
  validateIdListBody("ids"),
  asyncHandler(bulkDeleteTransactions)
);

export default router;
