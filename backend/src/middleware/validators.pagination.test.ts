import { describe, it, expect, vi } from 'vitest';
import type { Request, Response, NextFunction } from 'express';
import { parsePagination, validateIdListBody } from './validators';

function makeReq(overrides: Partial<Request> & { query?: any; body?: any } = {}): Request {
  return {
    query: {},
    body: {},
    ...overrides,
  } as Request;
}

describe('parsePagination', () => {
  it('sets default limit and zero offset', () => {
    const req = makeReq({ query: {} });
    const res = { status: vi.fn().mockReturnThis(), json: vi.fn() } as unknown as Response;
    const next = vi.fn() as NextFunction;

    parsePagination(50, 200)(req, res, next);

    expect(next).toHaveBeenCalled();
    expect((req as any).pagination).toEqual({ limit: 50, offset: 0 });
  });

  it('caps limit at maxLimit', () => {
    const req = makeReq({ query: { limit: '999', offset: '10' } });
    const res = { status: vi.fn().mockReturnThis(), json: vi.fn() } as unknown as Response;
    const next = vi.fn() as NextFunction;

    parsePagination(50, 200)(req, res, next);

    expect((req as any).pagination).toEqual({ limit: 200, offset: 10 });
  });

  it('rejects invalid limit', () => {
    const req = makeReq({ query: { limit: '0' } });
    const json = vi.fn();
    const res = { status: vi.fn().mockReturnValue({ json }) } as unknown as Response;
    const next = vi.fn() as NextFunction;

    parsePagination()(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });
});

describe('validateIdListBody', () => {
  it('normalizes ids array', () => {
    const req = makeReq({ body: { ids: [1, '2', 3] } });
    const res = { status: vi.fn().mockReturnThis(), json: vi.fn() } as unknown as Response;
    const next = vi.fn() as NextFunction;

    validateIdListBody('ids')(req, res, next);

    expect(next).toHaveBeenCalled();
    expect(req.body.ids).toEqual([1, 2, 3]);
  });

  it('rejects when too many ids', () => {
    const ids = Array.from({ length: 201 }, (_, i) => i + 1);
    const req = makeReq({ body: { ids } });
    const json = vi.fn();
    const res = { status: vi.fn().mockReturnValue({ json }) } as unknown as Response;
    const next = vi.fn() as NextFunction;

    validateIdListBody('ids')(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });
});
