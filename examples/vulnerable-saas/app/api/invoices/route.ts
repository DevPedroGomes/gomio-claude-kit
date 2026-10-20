import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { db } from "@/lib/db";

export async function GET(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { rows } = await db.query(
    "SELECT id, customer_name, amount_cents, created_at FROM invoices WHERE tenant_id = $1 ORDER BY created_at DESC LIMIT 100",
    [session.tenantId],
  );
  return NextResponse.json(rows);
}

export async function POST(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const body = await req.json();
  const amount = Number(body.amount_cents);
  if (typeof body.customer_name !== "string" || !Number.isInteger(amount) || amount <= 0) {
    return NextResponse.json({ error: "invalid invoice" }, { status: 400 });
  }

  const { rows } = await db.query(
    `INSERT INTO invoices (tenant_id, customer_name, customer_email, amount_cents, notes)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [session.tenantId, body.customer_name, body.customer_email ?? null, amount, body.notes ?? null],
  );
  return NextResponse.json({ id: rows[0].id }, { status: 201 });
}
