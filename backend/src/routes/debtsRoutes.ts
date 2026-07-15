import express from "express";
import { listDebts, createDebt, settleDebt, deleteDebt } from "../controllers/debtsController";
import { requireAuth } from "../middleware/requireAuth";
import { validateNumericParam } from "../middleware/validators";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

router.get("/", asyncHandler(listDebts));
router.post("/", asyncHandler(createDebt));
router.put("/:id/settle", validateNumericParam("id"), asyncHandler(settleDebt));
router.delete("/:id", validateNumericParam("id"), asyncHandler(deleteDebt));

export default router;
