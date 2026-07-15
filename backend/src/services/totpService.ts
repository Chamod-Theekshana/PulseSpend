import crypto from 'crypto';
import { generateSecret, generateURI, verifySync } from 'otplib';
import { UserModel, type User } from '../models/UserModel';

const ISSUER = 'PulseSpend';
const RECOVERY_CODE_COUNT = 8;
// Accept codes from the adjacent 30s step too — phone clocks drift.
const EPOCH_TOLERANCE_SECONDS = 30;

export function hashRecoveryCode(code: string): string {
  return crypto.createHash('sha256').update(code.trim().toLowerCase()).digest('hex');
}

/** Generates a fresh secret + one-shot recovery codes for enrollment. */
export function generateEnrollment(email: string): {
  secret: string;
  otpauthUrl: string;
  recoveryCodes: string[];
  recoveryHashes: string[];
} {
  const secret = generateSecret();
  const otpauthUrl = generateURI({ secret, issuer: ISSUER, label: email });
  // 8 codes of the form xxxx-xxxx (hex) — easy to read out or write down.
  const recoveryCodes = Array.from({ length: RECOVERY_CODE_COUNT }, () => {
    const hex = crypto.randomBytes(4).toString('hex');
    return `${hex.slice(0, 4)}-${hex.slice(4)}`;
  });
  return { secret, otpauthUrl, recoveryCodes, recoveryHashes: recoveryCodes.map(hashRecoveryCode) };
}

export function verifyTotpCode(secret: string, code: string): boolean {
  try {
    return verifySync({
      token: code.replace(/\s/g, ''),
      secret,
      epochTolerance: EPOCH_TOLERANCE_SECONDS,
    }).valid;
  } catch {
    return false;
  }
}

/**
 * Second-factor check used by sign-in and disable: a 6-digit authenticator
 * code, or (fallback) a one-shot recovery code which is consumed on success.
 */
export async function verifySecondFactor(user: User, code: string): Promise<boolean> {
  const trimmed = String(code || '').trim();
  if (!trimmed || !user.totp_secret) return false;
  if (/^\d{6}$/.test(trimmed.replace(/\s/g, '')) && verifyTotpCode(user.totp_secret, trimmed)) {
    return true;
  }
  return UserModel.consumeRecoveryCode(String(user.id), hashRecoveryCode(trimmed));
}
