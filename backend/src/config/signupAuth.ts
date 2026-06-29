import crypto from 'crypto';
import { randomInt } from 'crypto';

export interface SignupSession {
  email: string;
  otpHash: string;
  otpExpiresAt: number;
  otpAttempts: number;
  lastResendAt: number;
  signupTokenHash?: string;
  signupTokenExpiresAt?: number;
}

const signupStore = new Map<string, SignupSession>();

const OTP_EXPIRY = 5 * 60 * 1000; // 5 minutes
const SIGNUP_TOKEN_EXPIRY = 10 * 60 * 1000; // 10 minutes
const RESEND_COOLDOWN = 30 * 1000; // 30 seconds
const MAX_ATTEMPTS = 5;

export function generateOTP(): string {
  return randomInt(100000, 1000000).toString();
}

export function generateSignupToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function hashValue(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function storeOTP(email: string, otp: string): void {
  const now = Date.now();
  const existing = signupStore.get(email);
  
  signupStore.set(email, {
    email,
    otpHash: hashValue(otp),
    otpExpiresAt: now + OTP_EXPIRY,
    otpAttempts: 0,
    lastResendAt: now,
    signupTokenHash: existing?.signupTokenHash,
    signupTokenExpiresAt: existing?.signupTokenExpiresAt,
  });
}

export function verifyOTP(email: string, otp: string): { valid: boolean; message: string; signupToken?: string } {
  const session = signupStore.get(email);

  if (!session) {
    return { valid: false, message: 'No passkey found for this email' };
  }

  if (Date.now() > session.otpExpiresAt) {
    return { valid: false, message: 'Passkey expired' };
  }

  if (session.otpAttempts >= MAX_ATTEMPTS) {
    signupStore.delete(email);
    return { valid: false, message: 'Max attempts exceeded' };
  }

  session.otpAttempts++;

  if (hashValue(otp) === session.otpHash) {
    const signupToken = generateSignupToken();
    session.signupTokenHash = hashValue(signupToken);
    session.signupTokenExpiresAt = Date.now() + SIGNUP_TOKEN_EXPIRY;
    return { valid: true, message: 'Passkey verified', signupToken };
  }

  return { valid: false, message: 'Invalid passkey' };
}

export function verifySignupToken(email: string, token: string): { valid: boolean; message: string } {
  const session = signupStore.get(email);

  if (!session || !session.signupTokenHash) {
    return { valid: false, message: 'Invalid or expired signup session' };
  }

  if (Date.now() > (session.signupTokenExpiresAt || 0)) {
    return { valid: false, message: 'Signup session expired' };
  }

  if (hashValue(token) !== session.signupTokenHash) {
    return { valid: false, message: 'Invalid signup token' };
  }

  return { valid: true, message: 'Token valid' };
}

export function clearSignupSession(email: string): void {
  signupStore.delete(email);
}

export function canResendOTP(email: string): { allowed: boolean; waitSeconds: number } {
  const session = signupStore.get(email);

  if (!session) {
    return { allowed: true, waitSeconds: 0 };
  }

  const timeSinceLastResend = Date.now() - session.lastResendAt;
  if (timeSinceLastResend < RESEND_COOLDOWN) {
    return { allowed: false, waitSeconds: Math.ceil((RESEND_COOLDOWN - timeSinceLastResend) / 1000) };
  }

  return { allowed: true, waitSeconds: 0 };
}

export function validatePassword(password: string): { valid: boolean; message: string } {
  if (password.length < 8) {
    return { valid: false, message: 'Password must be at least 8 characters' };
  }
  if (!/[A-Z]/.test(password)) {
    return { valid: false, message: 'Password must contain at least 1 uppercase letter' };
  }
  if (!/[0-9]/.test(password)) {
    return { valid: false, message: 'Password must contain at least 1 number' };
  }
  return { valid: true, message: 'Password valid' };
}
