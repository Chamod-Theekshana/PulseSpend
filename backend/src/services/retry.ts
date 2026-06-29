type RetryOptions = {
  retries?: number;
  delayMs?: number;
  backoffFactor?: number;
};

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function withRetries<T>(fn: () => Promise<T>, options: RetryOptions = {}): Promise<T> {
  const retries = options.retries ?? 2;
  const delayMs = options.delayMs ?? 500;
  const backoffFactor = options.backoffFactor ?? 2;

  let attempt = 0;
  let lastError: unknown;

  while (attempt <= retries) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (attempt === retries) break;
      const waitMs = Math.round(delayMs * Math.pow(backoffFactor, attempt));
      await wait(waitMs);
      attempt += 1;
    }
  }

  throw lastError;
}
