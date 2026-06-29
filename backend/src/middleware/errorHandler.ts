import type { NextFunction, Request, Response } from 'express';

export function errorHandler(err: any, req: Request, res: Response, _next: NextFunction) {
  const status = err?.status || err?.statusCode || 500;
  const message = status < 500 ? (err?.message || 'Bad Request') : 'Server Error';

  if (status >= 500) {
    console.error('[ErrorHandler] Unhandled error:', err);
  }

  if (res.headersSent) return;
  res.status(status).json({ message });
}
