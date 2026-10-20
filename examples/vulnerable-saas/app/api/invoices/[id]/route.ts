import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { db } from "@/lib/db";

type Params = { params: Promise<{ id: string }> };

export async function GET(req: NextRequest, { params }: Params) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { id } = await params;
  const { rows } = await db.query(
    "SELECT id, customer_name, customer_email, amount_cents, notes, created_at FROM invoices WHERE id = $1",
    [id],
  );
  if (!rows[0]) return NextResponse.json({ error: "not found" }, { status: 404 });
  return NextResponse.json(rows[0]);
}

export async function DELETE(req: NextRequest, { params }: Params) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { id } = await params;
  const { rowCount } = await db.query(
    "DELETE FROM invoices WHERE id = $1 AND tenant_id = $2",
    [id, session.tenantId],
  );
  if (!rowCount) return NextResponse.json({ error: "not found" }, { status: 404 });
  return new NextResponse(null, { status: 204 });
}
