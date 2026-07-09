import type { NextFunction, Request, Response } from 'express';
import { isTransientDbError } from '../config/db';

export function errorHandler(err: any, req: Request, res: Response, _next: NextFunction) {
  // Transient database connectivity blips → 503 with a clear, retryable message
  // (and a concise log line, not a full stack dump).
  if (err?.isDbConnectionError || isTransientDbError(err)) {
    console.warn(
      `[ErrorHandler] Database temporarily unreachable on ${req.method} ${req.path}:`,
      err?.message,
    );
    if (res.headersSent) return;
    return res.status(503).json({
      message: 'Service temporarily unavailable. Please check your connection and try again.',
      retryable: true,
    });
  }

  const status = err?.status || err?.statusCode || 500;
  const message = status < 500 ? (err?.message || 'Bad Request') : 'Server Error';

  if (status >= 500) {
    console.error('[ErrorHandler] Unhandled error:', err);
  }

  if (res.headersSent) return;
  res.status(status).json({ message });
}
