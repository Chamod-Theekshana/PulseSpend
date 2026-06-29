import { randomInt, createHash } from 'crypto';

export interface OTPRecord {
  email: string;
  hashedOtp: string;
  attempts: number;
  expiresAt: number;
  createdAt: number;
  lastResendAt: number;
}

const otpStore = new Map<string, OTPRecord>();

const RESEND_COOLDOWN = 30 * 1000; // 30 seconds
const OTP_EXPIRY = 5 * 60 * 1000;  // 5 minutes
const MAX_ATTEMPTS = 5;

/**
 * Generates a cryptographically secure 6-digit OTP.
 */
export function generateOTP(): string {
  return randomInt(100000, 1000000).toString();
}

export function hashOTP(otp: string): string {
  return createHash('sha256').update(otp).digest('hex');
}

export function storeOTP(email: string, otp: string): void {
  const now = Date.now();
  otpStore.set(email, {
    email,
    hashedOtp: hashOTP(otp),
    attempts: 0,
    expiresAt: now + OTP_EXPIRY,
    createdAt: now,
    lastResendAt: now,
  });
}

export function verifyOTP(email: string, otp: string): { valid: boolean; message: string } {
  const record = otpStore.get(email);

  if (!record) {
    return { valid: false, message: 'No OTP found for this email' };
  }

  if (Date.now() > record.expiresAt) {
    otpStore.delete(email);
    return { valid: false, message: 'OTP has expired. Please request a new one.' };
  }

  if (record.attempts >= MAX_ATTEMPTS) {
    otpStore.delete(email);
    return { valid: false, message: 'Too many incorrect attempts. Please request a new OTP.' };
  }

  record.attempts++;

  if (hashOTP(String(otp)) === record.hashedOtp) {
    otpStore.delete(email);
    return { valid: true, message: 'OTP verified' };
  }

  const remaining = MAX_ATTEMPTS - record.attempts;
  return { valid: false, message: `Invalid OTP. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.` };
}

export function canResendOTP(email: string): { allowed: boolean; waitSeconds: number } {
  const record = otpStore.get(email);

  if (!record) {
    return { allowed: true, waitSeconds: 0 };
  }

  const timeSinceLastResend = Date.now() - record.lastResendAt;
  if (timeSinceLastResend < RESEND_COOLDOWN) {
    return { allowed: false, waitSeconds: Math.ceil((RESEND_COOLDOWN - timeSinceLastResend) / 1000) };
  }

  return { allowed: true, waitSeconds: 0 };
}

export function updateResendTime(email: string): void {
  const record = otpStore.get(email);
  if (record) {
    record.lastResendAt = Date.now();
  }
}
