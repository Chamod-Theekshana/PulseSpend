import bcrypt from 'bcrypt';
import { UserModel } from '../models/UserModel';
import { generateEnrollment, verifyTotpCode, verifySecondFactor } from '../services/totpService';
import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';

/**
 * Step 1 of enrollment: mint a secret + recovery codes. 2FA is NOT active yet —
 * the user must prove their authenticator works via /auth/2fa/verify first, so
 * a mis-scanned QR can never lock them out.
 */
export async function enrollTwoFactor(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const user = await UserModel.findById(userId);
  if (!user) return res.status(404).json({ message: 'User not found' });
  if (user.totp_enabled) {
    return res.status(409).json({ message: 'Two-factor authentication is already enabled' });
  }

  const { secret, otpauthUrl, recoveryCodes, recoveryHashes } = generateEnrollment(user.email);
  await UserModel.setTotpSecret(userId, secret, recoveryHashes);

  return res.status(200).json({
    message: 'Scan the QR code with your authenticator app, then verify a code',
    secret,
    otpauth_url: otpauthUrl,
    recovery_codes: recoveryCodes,
  });
}

/** Step 2 of enrollment: a valid code from the authenticator turns 2FA on. */
export async function verifyTwoFactorEnrollment(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const code = String(req.body?.code ?? '').trim();
  if (!code) return res.status(400).json({ message: 'code is required' });

  const user = await UserModel.findById(userId);
  if (!user || !user.totp_secret) {
    return res.status(400).json({ message: 'Start enrollment first' });
  }
  if (user.totp_enabled) {
    return res.status(409).json({ message: 'Two-factor authentication is already enabled' });
  }
  if (!verifyTotpCode(user.totp_secret, code)) {
    return res.status(401).json({ message: 'Invalid code — check your authenticator app' });
  }

  await UserModel.enableTotp(userId);
  return res.status(200).json({ message: 'Two-factor authentication enabled', totp_enabled: true });
}

/** Turning 2FA off needs the password AND a current code (or recovery code). */
export async function disableTwoFactor(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { password, code } = req.body ?? {};
  if (!password || !code) {
    return res.status(400).json({ message: 'password and code are required' });
  }

  const user = await UserModel.findById(userId);
  if (!user) return res.status(404).json({ message: 'User not found' });
  if (!user.totp_enabled) {
    return res.status(400).json({ message: 'Two-factor authentication is not enabled' });
  }

  const passwordOk = await bcrypt.compare(String(password), user.password);
  if (!passwordOk) return res.status(401).json({ message: 'Incorrect password' });

  const codeOk = await verifySecondFactor(user, String(code));
  if (!codeOk) return res.status(401).json({ message: 'Invalid two-factor code' });

  await UserModel.disableTotp(userId);
  return res.status(200).json({ message: 'Two-factor authentication disabled', totp_enabled: false });
}

/** Lets the settings screen show the current 2FA state. */
export async function getTwoFactorStatus(req: AuthedRequest, res: Response) {
  const user = await UserModel.findById(String(req.user!.id));
  if (!user) return res.status(404).json({ message: 'User not found' });
  return res.status(200).json({ totp_enabled: !!user.totp_enabled });
}
