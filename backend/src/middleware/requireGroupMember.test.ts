import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { Response, NextFunction } from 'express';

// The guard reaches into GroupModel, which imports the Neon pool. Mock the
// model so these stay pure unit tests with no database.
vi.mock('../models/GroupModel', () => ({
  GroupModel: { isMember: vi.fn() },
}));

import { GroupModel } from '../models/GroupModel';
import { GroupMembershipCache } from '../config/groupMembershipCache';
import { requireGroupMember } from './requireGroupMember';
import type { AuthedRequest } from './requireAuth';

const isMember = GroupModel.isMember as unknown as ReturnType<typeof vi.fn>;

function makeReq(userId?: string, groupId?: string): AuthedRequest {
  return {
    user: userId ? { id: Number(userId), email: 'a@b.c' } : undefined,
    params: groupId ? { id: groupId } : {},
  } as unknown as AuthedRequest;
}

function makeRes() {
  const res = {
    statusCode: 0,
    body: undefined as any,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: any) {
      this.body = payload;
      return this;
    },
  };
  return res as unknown as Response & { statusCode: number; body: any };
}

beforeEach(() => {
  GroupMembershipCache.clear();
  isMember.mockReset();
});

afterEach(() => {
  GroupMembershipCache.clear();
});

describe('requireGroupMember', () => {
  it('calls next() for a genuine member', async () => {
    isMember.mockResolvedValue(true);
    const req = makeReq('7', '42');
    const res = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(req, res, next);

    expect(next).toHaveBeenCalledOnce();
    expect(res.statusCode).toBe(0);
  });

  it('403s a signed-in non-member', async () => {
    isMember.mockResolvedValue(false);
    const req = makeReq('7', '42');
    const res = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(403);
  });

  it('403s when there is no authenticated user', async () => {
    const req = makeReq(undefined, '42');
    const res = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(403);
    // Must not have been asked to hit the database at all.
    expect(isMember).not.toHaveBeenCalled();
  });

  it('403s when the group id param is absent', async () => {
    const req = makeReq('7', undefined);
    const res = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(req, res, next);

    expect(res.statusCode).toBe(403);
    expect(isMember).not.toHaveBeenCalled();
  });

  it('forwards unexpected errors to the error handler rather than allowing through', async () => {
    isMember.mockRejectedValue(new Error('db down'));
    const req = makeReq('7', '42');
    const res = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(req, res, next);

    // next(err) — NOT next() — so the request fails closed with a 5xx.
    expect(next).toHaveBeenCalledOnce();
    expect((next as any).mock.calls[0][0]).toBeInstanceOf(Error);
  });

  it('serves a repeat check from cache instead of re-querying', async () => {
    isMember.mockResolvedValue(true);
    const next = vi.fn() as unknown as NextFunction;

    await requireGroupMember('id')(makeReq('7', '42'), makeRes(), next);
    await requireGroupMember('id')(makeReq('7', '42'), makeRes(), next);
    await requireGroupMember('id')(makeReq('7', '42'), makeRes(), next);

    expect(isMember).toHaveBeenCalledOnce();
  });

  it('does not leak one user\u2019s cached membership to another', async () => {
    isMember.mockImplementation(async (_g: any, u: string) => u === '7');
    const nextA = vi.fn() as unknown as NextFunction;
    const nextB = vi.fn() as unknown as NextFunction;
    const resB = makeRes();

    await requireGroupMember('id')(makeReq('7', '42'), makeRes(), nextA);
    await requireGroupMember('id')(makeReq('8', '42'), resB, nextB);

    expect(nextA).toHaveBeenCalledOnce();
    expect(nextB).not.toHaveBeenCalled();
    expect(resB.statusCode).toBe(403);
  });

  it('does not leak membership in one group into another', async () => {
    isMember.mockImplementation(async (g: any) => String(g) === '42');
    const nextIn = vi.fn() as unknown as NextFunction;
    const nextOut = vi.fn() as unknown as NextFunction;
    const resOut = makeRes();

    await requireGroupMember('id')(makeReq('7', '42'), makeRes(), nextIn);
    await requireGroupMember('id')(makeReq('7', '99'), resOut, nextOut);

    expect(nextIn).toHaveBeenCalledOnce();
    expect(nextOut).not.toHaveBeenCalled();
    expect(resOut.statusCode).toBe(403);
  });
});

describe('GroupMembershipCache', () => {
  it('returns null on a miss', () => {
    expect(GroupMembershipCache.get('1', 'u')).toBeNull();
  });

  it('round-trips a positive and a negative result', () => {
    GroupMembershipCache.set('1', 'u', true);
    GroupMembershipCache.set('2', 'u', false);
    expect(GroupMembershipCache.get('1', 'u')).toBe(true);
    expect(GroupMembershipCache.get('2', 'u')).toBe(false);
  });

  it('invalidates a single pair', () => {
    GroupMembershipCache.set('1', 'u', true);
    GroupMembershipCache.invalidate('1', 'u');
    expect(GroupMembershipCache.get('1', 'u')).toBeNull();
  });

  it('invalidates every member of a group at once', () => {
    GroupMembershipCache.set('1', 'a', true);
    GroupMembershipCache.set('1', 'b', true);
    GroupMembershipCache.set('2', 'a', true);

    GroupMembershipCache.invalidate('1');

    expect(GroupMembershipCache.get('1', 'a')).toBeNull();
    expect(GroupMembershipCache.get('1', 'b')).toBeNull();
    // A different group must be untouched.
    expect(GroupMembershipCache.get('2', 'a')).toBe(true);
  });

  it('expires a negative result sooner than a positive one', () => {
    vi.useFakeTimers();
    try {
      GroupMembershipCache.set('1', 'yes', true);
      GroupMembershipCache.set('1', 'no', false);

      // Past the 5s negative TTL, short of the 30s positive TTL.
      vi.advanceTimersByTime(10_000);

      expect(GroupMembershipCache.get('1', 'no')).toBeNull();
      expect(GroupMembershipCache.get('1', 'yes')).toBe(true);

      // Now past the positive TTL too.
      vi.advanceTimersByTime(25_000);
      expect(GroupMembershipCache.get('1', 'yes')).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });
});
