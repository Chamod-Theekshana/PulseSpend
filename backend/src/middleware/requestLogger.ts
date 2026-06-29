import type { NextFunction, Request, Response } from 'express';

export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    // Basic structured-ish logging without extra deps.
    const path = req.originalUrl.split('?')[0];
    console.log(
      JSON.stringify({
        ts: new Date().toISOString(),
        method: req.method,
        path,
        status: res.statusCode,
        ms,
      }),
    );
  });
  next();
}
