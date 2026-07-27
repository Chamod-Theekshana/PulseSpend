import express from 'express';
import { sendOTP, verifyOTPAndSignUp } from '../controllers/otpController';
import { asyncHandler } from '../middleware/asyncHandler';
import { authRateLimiter } from '../middleware/RateLimiter';

const router = express.Router();

router.post('/send', authRateLimiter, asyncHandler(sendOTP));
router.post('/verify', authRateLimiter, asyncHandler(verifyOTPAndSignUp));

export default router;
