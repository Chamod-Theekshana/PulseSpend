import type { NextFunction, Request, Response } from 'express';
import { verifyAccessToken, type JwtUserPayload } from '../utils/jwt';
import { UserModel } from '../models/UserModel';
import { TokenVersionCache } from '../config/tokenVersionCache';

export type AuthedRequest = Request & { user?: JwtUserPayload };

export async function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  try {
    const auth = req.headers.authorization || '';
    const [scheme, token] = auth.split(' ');
    if (scheme !== 'Bearer' || !token) {
      return res.status(401).json({ message: 'Unauthorized' });
    }
    const user = verifyAccessToken(token);
    const userId = String(user.id);
    
    let tokenVersion = TokenVersionCache.get(userId);
    if (tokenVersion === null) {
      tokenVersion = await UserModel.getTokenVersion(userId);
      if (tokenVersion !== null) {
        TokenVersionCache.set(userId, tokenVersion);
      }
    }

    if (tokenVersion === null || tokenVersion !== (user.tokenVersion || 0)) {
      return res.status(401).json({ message: 'Unauthorized' });
    }
    req.user = user;
    return next();
  } catch (e: any) {
    return res.status(401).json({ message: 'Unauthorized' });
  }
}

export function requireUserMatchParam(paramName: string = 'user_id') {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    const authedId = String(req.user?.id || '');
    const requested = String((req.params as any)?.[paramName] || '');
    if (!authedId || !requested || authedId !== requested) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    return next();
  };
}
