import express from "express";
import {
  createGroup,
  listGroups,
  joinGroup,
  getMembers,
  getGroupTransactions,
  getGroupBalances,
  getGroupGoals,
  settleUp,
  leaveGroup,
} from "../controllers/groupsController";
import { requireAuth } from "../middleware/requireAuth";
import { validateNumericParam } from "../middleware/validators";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

router.get("/", asyncHandler(listGroups));
router.post("/", asyncHandler(createGroup));
router.post("/join", asyncHandler(joinGroup));
router.get("/:id/members", validateNumericParam("id"), asyncHandler(getMembers));
router.get("/:id/transactions", validateNumericParam("id"), asyncHandler(getGroupTransactions));
router.get("/:id/balances", validateNumericParam("id"), asyncHandler(getGroupBalances));
router.get("/:id/goals", validateNumericParam("id"), asyncHandler(getGroupGoals));
router.post("/:id/settle", validateNumericParam("id"), asyncHandler(settleUp));
router.delete("/:id/leave", validateNumericParam("id"), asyncHandler(leaveGroup));

export default router;
