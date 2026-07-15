import express from "express";
import { signUp, signIn, refreshToken, logout } from '../controllers/authController';
import { sendResetOTP, verifyResetOTP, completeReset } from '../controllers/passwordResetController';
import {
  enrollTwoFactor,
  verifyTwoFactorEnrollment,
  disableTwoFactor,
  getTwoFactorStatus,
} from '../controllers/twoFactorController';
import { asyncHandler } from '../middleware/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { authRateLimiter } from '../middleware/RateLimiter';

const router = express.Router();

router.post("/signup", authRateLimiter, asyncHandler(signUp));
router.post("/signin", authRateLimiter, asyncHandler(signIn));
router.post("/refresh", asyncHandler(refreshToken));
router.post("/logout", requireAuth, asyncHandler(logout));

// TOTP 2FA (enroll → verify → enabled; disable needs password + code)
router.get("/2fa/status", requireAuth, asyncHandler(getTwoFactorStatus));
router.post("/2fa/enroll", requireAuth, authRateLimiter, asyncHandler(enrollTwoFactor));
router.post("/2fa/verify", requireAuth, authRateLimiter, asyncHandler(verifyTwoFactorEnrollment));
router.post("/2fa/disable", requireAuth, authRateLimiter, asyncHandler(disableTwoFactor));

// Self-service password reset (email OTP → token → new password)
router.post("/reset/send", authRateLimiter, asyncHandler(sendResetOTP));
router.post("/reset/verify", authRateLimiter, asyncHandler(verifyResetOTP));
router.post("/reset/complete", authRateLimiter, asyncHandler(completeReset));

export default router;
