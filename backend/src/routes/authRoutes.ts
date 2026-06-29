import express from "express";
import { signUp, signIn, refreshToken, logout } from '../controllers/authController';
import { asyncHandler } from '../middleware/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';

const router = express.Router();

router.post("/signup", asyncHandler(signUp));
router.post("/signin", asyncHandler(signIn));
router.post("/refresh", asyncHandler(refreshToken));
router.post("/logout", requireAuth, asyncHandler(logout));

export default router;
