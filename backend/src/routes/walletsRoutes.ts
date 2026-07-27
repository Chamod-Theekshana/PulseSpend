import express from "express";
import {
  listWallets,
  getWalletBalances,
  getNetWorth,
  getBalanceHistory,
  createWallet,
  updateWallet,
  deleteWallet,
  transferBetweenWallets,
  correctOpeningBalance,
} from "../controllers/walletsController";
import { requireAuth } from "../middleware/requireAuth";
import { validateNumericParam } from "../middleware/validators";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

router.get("/", asyncHandler(listWallets));
router.get("/balances", asyncHandler(getWalletBalances));
router.get("/net-worth", asyncHandler(getNetWorth));
router.get("/balance-history", asyncHandler(getBalanceHistory));
router.post("/", asyncHandler(createWallet));
router.post("/transfer", asyncHandler(transferBetweenWallets));
router.put("/:id", validateNumericParam("id"), asyncHandler(updateWallet));
// Rewrites the wallet's opening seed, so it's separate from the plain update.
router.put("/:id/opening-balance", validateNumericParam("id"), asyncHandler(correctOpeningBalance));
router.delete("/:id", validateNumericParam("id"), asyncHandler(deleteWallet));

export default router;
