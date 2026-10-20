import { NextRequest, NextResponse } from "next/server";
import { addCredits } from "@/lib/credits";

// Stripe sends checkout.session.completed after a credit pack is paid.
export async function POST(req: NextRequest) {
  const event = await req.json();

  if (event.type === "checkout.session.completed") {
    const { tenantId, credits } = event.data.object.metadata ?? {};
    if (tenantId && credits) {
      await addCredits(tenantId, Number(credits));
    }
  }

  return NextResponse.json({ received: true });
}
