import express from 'express';
import { sendPasskey, verifyPasskey, setPassword } from '../controllers/signupController';
import { asyncHandler } from '../middleware/asyncHandler';

const router = express.Router();

router.post('/send-passkey', asyncHandler(sendPasskey));
router.post('/verify-passkey', asyncHandler(verifyPasskey));
router.post('/set-password', asyncHandler(setPassword));

export default router;
