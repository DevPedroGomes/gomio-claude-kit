import { NextRequest, NextResponse } from "next/server";
import { anthropic, DEFAULT_MODEL } from "@/lib/ai";

// Used by the public landing page demo: paste an invoice, get a summary.
export async function POST(req: NextRequest) {
  const { text, model, max_tokens } = await req.json();
  if (typeof text !== "string" || text.length === 0) {
    return NextResponse.json({ error: "text is required" }, { status: 400 });
  }

  const message = await anthropic.messages.create({
    model: model ?? DEFAULT_MODEL,
    max_tokens: max_tokens ?? 1024,
    messages: [{ role: "user", content: `Summarize this invoice for an accountant:\n\n${text}` }],
  });

  const summary = message.content.find((block) => block.type === "text");
  return NextResponse.json({ summary: summary?.type === "text" ? summary.text : "" });
}
