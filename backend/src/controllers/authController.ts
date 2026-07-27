import { UserModel } from '../models/UserModel';
import bcrypt from 'bcrypt';
import { signAccessToken, signRefreshToken, verifyRefreshToken } from '../utils/jwt';
import { CategoryModel } from '../models/CategoryModel';
import { BCRYPT_ROUNDS } from '../config/security';
import { loginFailRatelimit } from '../config/upstash';
import { verifySecondFactor } from '../services/totpService';
import type { Request, Response } from 'express';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Record a failed sign-in for an account and report whether it is now locked
 * out. Consumes a lockout token only on failure, so successful logins are never
 * throttled. Fails open (returns false) if the limiter is unavailable — per-IP
 * `authRateLimiter` still guards the Redis-down case by failing closed.
 */
async function isLockedAfterFailure(email: string): Promise<boolean> {
  try {
    const { success } = await loginFailRatelimit.limit(email);
    return !success;
  } catch (err) {
    console.error('[Auth] Login-failure counter unavailable:', err);
    return false;
  }
}

export async function signUp(req: Request, res: Response) {
  const { email, password } = req.body ?? {};

  if (!email || !password) {
    return res.status(400).json({ message: 'Email and password are required' });
  }

  if (!EMAIL_REGEX.test(String(email))) {
    return res.status(400).json({ message: 'Invalid email address' });
  }

  if (String(password).length < 8) {
    return res.status(400).json({ message: 'Password must be at least 8 characters' });
  }

  const normalizedEmail = String(email).toLowerCase().trim();
  const existing = await UserModel.findByEmail(normalizedEmail);
  if (existing) {
    return res.status(409).json({ message: 'Email already registered' });
  }

  const hashedPassword = await bcrypt.hash(String(password), BCRYPT_ROUNDS);
  const user = await UserModel.create(normalizedEmail, hashedPassword);

  // Best-effort: seed default categories — must not fail signup after user insert
  try {
    await CategoryModel.seedDefaults(String(user.id));
  } catch (seedErr) {
    console.error('[SignUp] Failed to seed default categories (account still created):', seedErr);
  }

  const tokenVersion = user.token_version || 0;
  const token = signAccessToken({ id: user.id, email: user.email, tokenVersion });
  const refreshToken = signRefreshToken({ id: user.id, email: user.email, tokenVersion });

  return res.status(201).json({
    message: 'Account created successfully',
    token,
    refreshToken,
    user: { id: user.id, email: user.email },
  });
}

export async function signIn(req: Request, res: Response) {
  const { email, password } = req.body ?? {};

  if (!email || !password) {
    return res.status(400).json({ message: 'Email and password are required' });
  }

  const normalizedEmail = String(email).toLowerCase().trim();
  const user = await UserModel.findByEmail(normalizedEmail);

  if (!user) {
    const locked = await isLockedAfterFailure(normalizedEmail);
    return res.status(locked ? 429 : 401).json({
      message: locked
        ? 'Too many failed attempts. Please try again later.'
        : 'Invalid email or password',
    });
  }

  const isValidPassword = await bcrypt.compare(String(password), user.password);
  if (!isValidPassword) {
    const locked = await isLockedAfterFailure(normalizedEmail);
    return res.status(locked ? 429 : 401).json({
      message: locked
        ? 'Too many failed attempts. Please try again later.'
        : 'Invalid email or password',
    });
  }

  // TOTP 2FA: password alone is not enough once enabled. The 202 tells the
  // client to re-submit the same credentials plus totp_code (or a recovery
  // code). Failed codes count toward the same lockout as failed passwords.
  if (user.totp_enabled) {
    const totpCode = String((req.body ?? {}).totp_code ?? '').trim();
    if (!totpCode) {
      return res.status(202).json({
        message: 'Two-factor code required',
        twoFactorRequired: true,
      });
    }
    const codeOk = await verifySecondFactor(user, totpCode);
    if (!codeOk) {
      const locked = await isLockedAfterFailure(normalizedEmail);
      return res.status(locked ? 429 : 401).json({
        message: locked
          ? 'Too many failed attempts. Please try again later.'
          : 'Invalid two-factor code',
        twoFactorRequired: true,
      });
    }
  }

  const tokenVersion = user.token_version || 0;
  const token = signAccessToken({ id: user.id, email: user.email, tokenVersion });
  const refreshToken = signRefreshToken({ id: user.id, email: user.email, tokenVersion });

  return res.status(200).json({
    message: 'Sign in successful',
    token,
    refreshToken,
    user: { id: user.id, email: user.email },
    // Signing in during the deletion grace window: the client offers a
    // restore ("cancel deletion") dialog when this is set.
    ...(user.deletion_requested_at
      ? { deletion_requested_at: user.deletion_requested_at }
      : {}),
  });
}

export async function refreshToken(req: Request, res: Response) {
  try {
    const { refreshToken } = req.body ?? {};
    if (!refreshToken) {
      return res.status(400).json({ message: 'refreshToken is required' });
    }

    const payload = verifyRefreshToken(String(refreshToken));
    const user = await UserModel.findById(String(payload.id));
    if (!user) {
      return res.status(401).json({ message: 'Unauthorized' });
    }

    const tokenVersion = user.token_version || 0;
    if ((payload.tokenVersion || 0) !== tokenVersion) {
      return res.status(401).json({ message: 'Unauthorized' });
    }

    const newAccessToken = signAccessToken({ id: user.id, email: user.email, tokenVersion });
    const newRefreshToken = signRefreshToken({ id: user.id, email: user.email, tokenVersion });

    return res.status(200).json({ token: newAccessToken, refreshToken: newRefreshToken });
  } catch (error) {
    console.error('Error refreshing token:', error);
    return res.status(401).json({ message: 'Unauthorized' });
  }
}

export async function logout(req: Request, res: Response) {
  try {
    const userId = String((req as any).user?.id || '');
    if (!userId) {
      return res.status(401).json({ message: 'Unauthorized' });
    }
    await UserModel.incrementTokenVersion(userId);
    return res.status(200).json({ message: 'Logged out' });
  } catch (error) {
    console.error('Error logging out:', error);
    return res.status(500).json({ message: 'Server Error' });
  }
}
