import bcrypt from 'bcrypt';
import { UserModel } from '../models/UserModel';
import { sendPasskeyEmail } from '../config/nodemailer';
import { BCRYPT_ROUNDS } from '../config/security';
import { sendPushToUser } from '../services/pushService';
import {
  generateOTP,
  storeOTP,
  verifyOTP,
  verifySignupToken,
  clearSignupSession,
  canResendOTP,
  validatePassword,
} from '../config/signupAuth';

/**
 * Self-service password reset. Reuses the signup OTP machinery (signupAuth.ts)
 * — its store is keyed by an opaque string, so reset sessions live under a
 * `reset:` prefix and can never collide with a signup session for the same
 * address. Flow: send OTP → verify OTP (→ short-lived reset token) → complete
 * with the token + new password.
 */
const key = (email: string) => `reset:${email}`;

export async function sendResetOTP(req: any, res: any) {
  const { email } = req.body ?? {};
  if (!email || !String(email).includes('@')) {
    return res.status(400).json({ message: 'Valid email is required' });
  }
  const normalizedEmail = String(email).toLowerCase().trim();

  // Inverse of signup: the account must EXIST. Respond identically either way
  // so this endpoint can't be used to probe which emails are registered.
  const user = await UserModel.findByEmail(normalizedEmail);

  const { allowed, waitSeconds } = canResendOTP(key(normalizedEmail));
  if (!allowed) {
    return res.status(429).json({ message: `Please wait ${waitSeconds}s before resending` });
  }

  if (user) {
    const otp = generateOTP();
    storeOTP(key(normalizedEmail), otp);
    try {
      await sendPasskeyEmail(normalizedEmail, otp);
    } catch (emailErr: any) {
      console.error('[Reset] Failed to send reset email:', emailErr?.message || emailErr);
      return res.status(503).json({
        message: 'Failed to send email. Please check your internet connection or try again later.',
      });
    }
  } else {
    console.log('[Reset] Ignoring reset request for unknown email');
  }

  return res.status(200).json({
    message: 'If that email is registered, a reset passkey has been sent.',
  });
}

export async function verifyResetOTP(req: any, res: any) {
  const { email, passkey } = req.body ?? {};
  if (!email || !passkey) {
    return res.status(400).json({ message: 'Email and passkey are required' });
  }
  const normalizedEmail = String(email).toLowerCase().trim();

  const { valid, message, signupToken } = verifyOTP(key(normalizedEmail), String(passkey));
  if (!valid) {
    return res.status(401).json({ message });
  }

  return res.status(200).json({ message: 'Passkey verified', resetToken: signupToken });
}

export async function completeReset(req: any, res: any) {
  const { email, password, resetToken } = req.body ?? {};
  if (!email || !password || !resetToken) {
    return res.status(400).json({ message: 'Email, password, and reset token are required' });
  }
  const normalizedEmail = String(email).toLowerCase().trim();

  const tokenCheck = verifySignupToken(key(normalizedEmail), String(resetToken));
  if (!tokenCheck.valid) {
    return res.status(401).json({ message: tokenCheck.message });
  }

  const passwordCheck = validatePassword(String(password));
  if (!passwordCheck.valid) {
    return res.status(400).json({ message: passwordCheck.message });
  }

  const user = await UserModel.findByEmail(normalizedEmail);
  if (!user) {
    clearSignupSession(key(normalizedEmail));
    return res.status(404).json({ message: 'Account not found' });
  }

  const hashed = await bcrypt.hash(String(password), BCRYPT_ROUNDS);
  await UserModel.updatePassword(String(user.id), hashed);
  // Kill every existing session/refresh token — the password may have leaked.
  await UserModel.incrementTokenVersion(String(user.id));
  clearSignupSession(key(normalizedEmail));

  // Best-effort security notification; never fail the reset over it.
  void sendPushToUser(
    String(user.id),
    'Password reset',
    'Your password was reset successfully. If this wasn\'t you, contact support immediately.',
    { type: 'security' },
  ).catch(() => {});

  return res.status(200).json({ message: 'Password reset successfully. Please sign in.' });
}
