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
  getSettlements,
  deleteSettlement,
  renameGroup,
  transferOwnership,
  removeMemberByOwner,
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
router.get("/:id/settlements", validateNumericParam("id"), asyncHandler(getSettlements));
router.delete("/:id/settlements/:sid", validateNumericParam("id"), validateNumericParam("sid"), asyncHandler(deleteSettlement));
router.put("/:id", validateNumericParam("id"), asyncHandler(renameGroup));
router.put("/:id/owner", validateNumericParam("id"), asyncHandler(transferOwnership));
router.delete("/:id/members/:userId", validateNumericParam("id"), asyncHandler(removeMemberByOwner));
router.delete("/:id/leave", validateNumericParam("id"), asyncHandler(leaveGroup));

export default router;
