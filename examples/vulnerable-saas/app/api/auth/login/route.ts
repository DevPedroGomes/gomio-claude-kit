import bcrypt from "bcryptjs";
import { NextRequest, NextResponse } from "next/server";
import { signSession } from "@/lib/auth";
import { db } from "@/lib/db";

export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (typeof email !== "string" || typeof password !== "string") {
    return NextResponse.json({ error: "invalid request" }, { status: 400 });
  }

  const { rows } = await db.query(
    "SELECT id, tenant_id, password_hash FROM users WHERE email = $1",
    [email.toLowerCase()],
  );
  const user = rows[0];
  const valid = user ? await bcrypt.compare(password, user.password_hash) : false;
  if (!valid) {
    return NextResponse.json({ error: "invalid email or password" }, { status: 401 });
  }

  const res = NextResponse.json({ ok: true });
  res.cookies.set("session", signSession({ userId: user.id, tenantId: user.tenant_id }), {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 12,
  });
  return res;
}
