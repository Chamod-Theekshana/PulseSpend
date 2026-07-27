import { describe, it, expect, beforeAll } from 'vitest';
import jwt from 'jsonwebtoken';
import {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
} from './jwt';

const SECRET = 'test-secret-that-is-at-least-32-characters-long';
const user = { id: 42, email: 'user@example.com', tokenVersion: 3 };

beforeAll(() => {
  process.env.JWT_SECRET = SECRET;
});

describe('jwt token-type separation', () => {
  it('round-trips an access token', () => {
    const payload = verifyAccessToken(signAccessToken(user));
    expect(payload).toEqual(user);
  });

  it('round-trips a refresh token', () => {
    const payload = verifyRefreshToken(signRefreshToken(user));
    expect(payload).toEqual(user);
  });

  it('rejects an access token used as a refresh token', () => {
    const access = signAccessToken(user);
    expect(() => verifyRefreshToken(access)).toThrow();
  });

  it('rejects a refresh token used as an access token', () => {
    const refresh = signRefreshToken(user);
    expect(() => verifyAccessToken(refresh)).toThrow();
  });

  it('rejects a legacy token that has no type claim', () => {
    const legacy = jwt.sign({ id: user.id, email: user.email, tokenVersion: 0 }, SECRET);
    expect(() => verifyAccessToken(legacy)).toThrow();
    expect(() => verifyRefreshToken(legacy)).toThrow();
  });

  it('rejects a token signed with the wrong secret', () => {
    const forged = jwt.sign({ id: 1, email: 'a@b.c', type: 'access' }, 'a-different-secret-value-32-chars-xx');
    expect(() => verifyAccessToken(forged)).toThrow();
  });
});
