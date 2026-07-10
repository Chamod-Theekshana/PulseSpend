import express from "express";
import { signUp, signIn, refreshToken, logout } from '../controllers/authController';
import { asyncHandler } from '../middleware/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { authRateLimiter } from '../middleware/RateLimiter';

const router = express.Router();

router.post("/signup", authRateLimiter, asyncHandler(signUp));
router.post("/signin", authRateLimiter, asyncHandler(signIn));
router.post("/refresh", asyncHandler(refreshToken));
router.post("/logout", requireAuth, asyncHandler(logout));

export default router;
