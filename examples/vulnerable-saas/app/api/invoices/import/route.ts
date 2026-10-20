import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";

// Imports an invoice from a link the customer pastes (e.g. a PDF or JSON export
// from their accounting tool) and returns its contents for the review screen.
export async function POST(req: NextRequest) {
  const session = getSession(req);
  if (!session) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { url } = await req.json();
  if (typeof url !== "string" || !/^https?:\/\//.test(url)) {
    return NextResponse.json({ error: "invalid url" }, { status: 400 });
  }

  const upstream = await fetch(url, { redirect: "follow" });
  const body = await upstream.text();
  return NextResponse.json({
    status: upstream.status,
    contentType: upstream.headers.get("content-type"),
    body: body.slice(0, 100_000),
  });
}
