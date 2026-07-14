import { UserModel } from '../models/UserModel';
import { sendPasskeyEmail } from '../config/nodemailer';
import {
  generateOTP,
  storeOTP,
  verifyOTP,
  verifySignupToken,
  clearSignupSession,
  canResendOTP,
  validatePassword,
} from '../config/signupAuth';
import bcrypt from 'bcrypt';
import { BCRYPT_ROUNDS } from '../config/security';
import { saveUserToken, sendPushToUser } from '../services/pushService';
import { signAccessToken, signRefreshToken } from '../utils/jwt';
import { CategoryModel } from '../models/CategoryModel';

export async function sendPasskey(req: any, res: any) {
  const { email } = req.body;

  if (!email || !email.includes('@')) {
    return res.status(400).json({ message: 'Valid email is required' });
  }

  const normalizedEmail = email.toLowerCase().trim();

  // Check if user already exists
  const existing = await UserModel.findByEmail(normalizedEmail);
  if (existing) {
    return res.status(400).json({ message: 'Email already registered' });
  }

  const { allowed, waitSeconds } = canResendOTP(normalizedEmail);
  if (!allowed) {
    return res.status(429).json({ message: `Please wait ${waitSeconds}s before resending` });
  }

  const otp = generateOTP();
  storeOTP(normalizedEmail, otp);

  try {
    await sendPasskeyEmail(normalizedEmail, otp);
  } catch (emailErr: any) {
    console.error('[Signup] Failed to send passkey email:', emailErr?.message || emailErr);
    return res.status(503).json({
      message: 'Failed to send email. Please check your internet connection or try again later.',
    });
  }

  res.status(200).json({ message: 'Passkey sent to email' });
}

export async function verifyPasskey(req: any, res: any) {
  const { email, passkey } = req.body;

  if (!email || !passkey) {
    return res.status(400).json({ message: 'Email and passkey are required' });
  }

  const normalizedEmail = email.toLowerCase().trim();

  const { valid, message, signupToken } = verifyOTP(normalizedEmail, passkey);

  if (!valid) {
    return res.status(401).json({ message });
  }

  res.status(200).json({
    message: 'Passkey verified',
    signupToken,
  });
}

export async function setPassword(req: any, res: any) {
  const { email, password, signupToken, fcm_token } = req.body;

  if (!email || !password || !signupToken) {
    return res.status(400).json({ message: 'Email, password, and signup token are required' });
  }

  const normalizedEmail = email.toLowerCase().trim();

  // Validate signup token
  const tokenCheck = verifySignupToken(normalizedEmail, signupToken);
  if (!tokenCheck.valid) {
    return res.status(401).json({ message: tokenCheck.message });
  }

  // Validate password
  const passwordCheck = validatePassword(password);
  if (!passwordCheck.valid) {
    return res.status(400).json({ message: passwordCheck.message });
  }

  // Check if user already exists
  const existing = await UserModel.findByEmail(normalizedEmail);
  if (existing) {
    clearSignupSession(normalizedEmail);
    return res.status(400).json({ message: 'Email already registered' });
  }

  // Hash password
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

  // Create user
  const user = await UserModel.create(normalizedEmail, passwordHash);

  // Best-effort: seed default categories — must not fail signup after user insert
  try {
    await CategoryModel.seedDefaults(String(user.id));
  } catch (seedErr) {
    console.error('[Signup] Failed to seed default categories (account still created):', seedErr);
  }

  // Clear signup session
  clearSignupSession(normalizedEmail);

  const tokenVersion = user.token_version || 0;
  const token = signAccessToken({ id: user.id, email: user.email, tokenVersion });
  const refreshToken = signRefreshToken({ id: user.id, email: user.email, tokenVersion });

  res.status(201).json({
    message: 'Account created successfully',
    token,
    refreshToken,
    user: {
      id: user.id,
      email: user.email,
      createdAt: user.created_at,
    },
  });

  // Fire-and-forget AFTER the response so a slow token save / FCM call never
  // delays signup (and never turns a post-insert failure into a 500 that makes
  // the client retry and hit "already registered").
  (async () => {
    try {
      // Register this device's push token first (if the client sent one) so the
      // welcome push below can actually be delivered to it.
      if (fcm_token && user.id) {
        console.log('[Push] Saving FCM token for new user:', user.id);
        await saveUserToken(String(user.id), String(fcm_token));
      }

      // Always create the welcome notification. sendPushToUser saves the in-app
      // inbox record even when no FCM token exists, so a brand-new user always
      // sees this in their notification inbox — and it's pushed too if a token
      // was registered above.
      await sendPushToUser(
        String(user.id),
        'Welcome to PulseSpend! 🎉',
        'Your account is ready. Start tracking your expenses and take control of your money.',
        { type: 'welcome' }
      );
      console.log('[Push] Welcome notification created for user:', user.id);
    } catch (err) {
      console.error('[Signup] Welcome notification failed (account still created):', err);
    }
  })();
}
