import express from "express";
import {
  listWallets,
  getWalletBalances,
  createWallet,
  updateWallet,
  deleteWallet,
} from "../controllers/walletsController";
import { requireAuth } from "../middleware/requireAuth";
import { validateNumericParam } from "../middleware/validators";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

router.get("/", asyncHandler(listWallets));
router.get("/balances", asyncHandler(getWalletBalances));
router.post("/", asyncHandler(createWallet));
router.put("/:id", validateNumericParam("id"), asyncHandler(updateWallet));
router.delete("/:id", validateNumericParam("id"), asyncHandler(deleteWallet));

export default router;
