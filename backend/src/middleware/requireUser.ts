import { Request, Response, NextFunction } from "express";
import { sql } from "../config/db";

export function requireUserFromParam(paramName: string = "user_id") {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idRaw = (req.params as any)[paramName];
      const id = Number(idRaw);
      const result = await sql`SELECT id, email, name, profile_photo, theme, biometric_enabled FROM users WHERE id = ${id}`;
      if (result.length === 0) {
        return res.status(404).json({ message: "User not found" });
      }
      (req as any).user = result[0];
      next();
    } catch (err) {
      console.error("requireUserFromParam error:", err);
      res.status(500).json({ message: "Server Error" });
    }
  };
}

export function requireUserFromBody(bodyField: string = "user_id") {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idRaw = (req.body as any)?.[bodyField];
      const id = Number(idRaw);
      const result = await sql`SELECT id, email, name, profile_photo, theme, biometric_enabled FROM users WHERE id = ${id}`;
      if (result.length === 0) {
        return res.status(404).json({ message: "User not found" });
      }
      (req as any).user = result[0];
      next();
    } catch (err) {
      console.error("requireUserFromBody error:", err);
      res.status(500).json({ message: "Server Error" });
    }
  };
}
