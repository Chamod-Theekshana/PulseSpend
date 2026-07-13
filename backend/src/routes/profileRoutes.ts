import express from "express";
import { exportUserData, importUserData, getProfile, updateProfile, updatePassword, deleteAccount } from "../controllers/profileController";
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

router.delete(
  "/:user_id",
  validateNumericParam("user_id"),
  requireUserMatchParam("user_id"),
  asyncHandler(deleteAccount)
);

export default router;
