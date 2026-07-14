import express from 'express';
import { sendPasskey, verifyPasskey, setPassword } from '../controllers/signupController';
import { asyncHandler } from '../middleware/asyncHandler';
import { authRateLimiter } from '../middleware/RateLimiter';

const router = express.Router();

router.post('/send-passkey', authRateLimiter, asyncHandler(sendPasskey));
router.post('/verify-passkey', authRateLimiter, asyncHandler(verifyPasskey));
router.post('/set-password', authRateLimiter, asyncHandler(setPassword));

export default router;
