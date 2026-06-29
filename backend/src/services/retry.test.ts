import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { withRetries } from './retry';

describe('withRetries', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns the result when the first attempt succeeds', async () => {
    const fn = vi.fn().mockResolvedValue(42);
    await expect(withRetries(fn, { retries: 2, delayMs: 10, backoffFactor: 2 })).resolves.toBe(42);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('retries on failure then succeeds', async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new Error('fail'))
      .mockResolvedValueOnce('ok');

    const p = withRetries(fn, { retries: 2, delayMs: 100, backoffFactor: 2 });
    await vi.advanceTimersByTimeAsync(150);
    await expect(p).resolves.toBe('ok');
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it('throws the last error after exhausting retries', async () => {
    const err = new Error('always');
    const fn = vi.fn().mockRejectedValue(err);
    const p = withRetries(fn, { retries: 1, delayMs: 50, backoffFactor: 1 });
    const settled = expect(p).rejects.toThrow('always');
    await vi.advanceTimersByTimeAsync(500);
    await settled;
    expect(fn).toHaveBeenCalledTimes(2);
  });
});
