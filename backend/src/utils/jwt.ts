import jwt from 'jsonwebtoken';

export type TokenType = 'access' | 'refresh';

export type JwtUserPayload = {
  id: number;
  email: string;
  tokenVersion?: number;
};

function getSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET is not set');
  }
  return secret;
}

function signToken(user: JwtUserPayload, type: TokenType, expiresIn: string): string {
  return jwt.sign(
    { id: user.id, email: user.email, tokenVersion: user.tokenVersion || 0, type },
    getSecret(),
    { expiresIn } as jwt.SignOptions,
  );
}

export function signAccessToken(user: JwtUserPayload): string {
  const expiresIn = (process.env.JWT_EXPIRES_IN || '15m') as string;
  return signToken(user, 'access', expiresIn);
}

export function signRefreshToken(user: JwtUserPayload): string {
  const expiresIn = (process.env.JWT_REFRESH_EXPIRES_IN || '30d') as string;
  return signToken(user, 'refresh', expiresIn);
}

function verifyToken(token: string, expectedType: TokenType): JwtUserPayload {
  const decoded = jwt.verify(token, getSecret());
  if (!decoded || typeof decoded !== 'object') {
    throw new Error('Invalid token');
  }
  // Enforce token-type separation: an access token must never be usable as a
  // refresh token (and vice-versa). Tokens issued before this claim existed
  // have no `type` and are rejected, forcing a clean re-login.
  if ((decoded as any).type !== expectedType) {
    throw new Error(`Expected a ${expectedType} token`);
  }
  const id = Number((decoded as any).id);
  const email = String((decoded as any).email || '');
  const tokenVersion = Number((decoded as any).tokenVersion || 0);
  if (!id || !email) throw new Error('Invalid token payload');
  return { id, email, tokenVersion };
}

export function verifyAccessToken(token: string): JwtUserPayload {
  return verifyToken(token, 'access');
}

export function verifyRefreshToken(token: string): JwtUserPayload {
  return verifyToken(token, 'refresh');
}
