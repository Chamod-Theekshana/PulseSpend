import express from "express";
import { signUp, signIn, refreshToken, logout } from '../controllers/authController';
import { sendResetOTP, verifyResetOTP, completeReset } from '../controllers/passwordResetController';
import { asyncHandler } from '../middleware/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { authRateLimiter } from '../middleware/RateLimiter';

const router = express.Router();

router.post("/signup", authRateLimiter, asyncHandler(signUp));
router.post("/signin", authRateLimiter, asyncHandler(signIn));
router.post("/refresh", asyncHandler(refreshToken));
router.post("/logout", requireAuth, asyncHandler(logout));

// Self-service password reset (email OTP → token → new password)
router.post("/reset/send", authRateLimiter, asyncHandler(sendResetOTP));
router.post("/reset/verify", authRateLimiter, asyncHandler(verifyResetOTP));
router.post("/reset/complete", authRateLimiter, asyncHandler(completeReset));

export default router;
