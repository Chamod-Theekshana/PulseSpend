import express from "express";
import { exportUserData, importUserData, getProfile, updateProfile, updatePassword, updateRoundup, deleteAccount, cancelDeletion } from "../controllers/profileController";
import { validateNumericParam, validateProfileUpdateBody } from "../middleware/validators";
import { requireAuth, requireUserMatchParam } from "../middleware/requireAuth";
import { asyncHandler } from "../middleware/asyncHandler";

const router = express.Router();

router.use(requireAuth);

router.get(
  "/:user_id/data-export",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(exportUserData)
);

router.post(
  "/:user_id/data-import",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(importUserData)
);

router.get(
  "/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(getProfile)
);

router.put(
  "/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  validateProfileUpdateBody,
  asyncHandler(updateProfile)
);

router.put(
  "/:user_id/password",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(updatePassword)
);

router.put(
  "/:user_id/roundup",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(updateRoundup)
);

router.delete(
  "/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(deleteAccount)
);

router.post(
  "/:user_id/cancel-deletion",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(cancelDeletion)
);

export default router;
