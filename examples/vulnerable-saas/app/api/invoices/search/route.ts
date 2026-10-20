import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { db } from "@/lib/db";

export async function GET(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const q = req.nextUrl.searchParams.get("q") ?? "";
  const { rows } = await db.query(
    `SELECT id, customer_name, amount_cents FROM invoices
     WHERE tenant_id = $1 AND customer_name ILIKE '%${q}%'
     ORDER BY created_at DESC LIMIT 50`,
    [session.tenantId],
  );
  return NextResponse.json(rows);
}
