import jwt from "jsonwebtoken";
import { NextRequest } from "next/server";

export type Session = { userId: string; tenantId: string };

const SECRET = process.env.JWT_SECRET;
if (!SECRET) {
  throw new Error("JWT_SECRET is not set");
}

export function signSession(session: Session): string {
  return jwt.sign(session, SECRET!, { algorithm: "HS256", expiresIn: "12h" });
}

export function getSession(req: NextRequest): Session | null {
  const token = req.cookies.get("session")?.value;
  if (!token) return null;
  try {
    const payload = jwt.verify(token, SECRET!, { algorithms: ["HS256"] }) as Session;
    return { userId: payload.userId, tenantId: payload.tenantId };
  } catch {
    return null;
  }
}
