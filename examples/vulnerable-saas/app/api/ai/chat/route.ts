import { NextRequest, NextResponse } from "next/server";
import { anthropic, DEFAULT_MODEL } from "@/lib/ai";
import { getSession } from "@/lib/auth";
import { debit, getBalance } from "@/lib/credits";

const COST_PER_MESSAGE = 1;

// Invoice assistant for signed-in customers. Each answer costs one credit.
export async function POST(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  if ((await getBalance(session.tenantId)) < COST_PER_MESSAGE) {
    return NextResponse.json({ error: "out of credits" }, { status: 402 });
  }

  const { question } = await req.json();
  if (typeof question !== "string" || question.length > 4000) {
    return NextResponse.json({ error: "invalid question" }, { status: 400 });
  }

  const message = await anthropic.messages.create({
    model: DEFAULT_MODEL,
    max_tokens: 800,
    messages: [{ role: "user", content: question }],
  });

  await debit(session.tenantId, COST_PER_MESSAGE);

  const answer = message.content.find((block) => block.type === "text");
  return NextResponse.json({ answer: answer?.type === "text" ? answer.text : "" });
}
