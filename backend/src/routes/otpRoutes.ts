import express from 'express';
import { sendOTP, verifyOTPAndSignUp } from '../controllers/otpController';
import { asyncHandler } from '../middleware/asyncHandler';

const router = express.Router();

router.post('/send', asyncHandler(sendOTP));
router.post('/verify', asyncHandler(verifyOTPAndSignUp));

export default router;
