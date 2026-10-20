import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { CREDIT_PACKS, stripe } from "@/lib/stripe";

export async function POST(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { pack } = await req.json();
  const selected = CREDIT_PACKS[pack as string];
  if (!selected) return NextResponse.json({ error: "unknown pack" }, { status: 400 });

  const checkout = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{ price: selected.priceId, quantity: 1 }],
    metadata: { tenantId: session.tenantId, credits: String(selected.credits) },
    success_url: `${process.env.APP_URL}/billing?status=success`,
    cancel_url: `${process.env.APP_URL}/billing?status=cancelled`,
  });
  return NextResponse.json({ url: checkout.url });
}
