# Real output: `/review-security full` on `examples/vulnerable-saas`

| | |
|---|---|
| Date | 2026-10-20 (run started 17:35 UTC) |
| Claude Code | 2.1.304 (`claude --version`) |
| Model | claude-opus-5-5 (every turn, including the verification sub-agents) |
| Kit commit | `dac7964` (the command file as of that commit) |
| Invocation | `claude -p "/review-security full" --model opus --setting-sources project --strict-mcp-config --output-format stream-json --verbose --max-budget-usd 25` |
| Target | a copy of `examples/vulnerable-saas` in a temporary directory, one git commit, the kit commands installed in its `.claude/commands/` |
| Reported by Claude Code | US$ 1.10 at API list prices, 110 s wall time across the result events, 16 turns, 6 Bash calls, 6 verification sub-agents |
| Permission denials | 4 Bash calls were refused in headless mode (they were not pre-approved and nobody could answer a prompt) |

The verification sub-agents ran in the background, so the session ended its turn while waiting for them and resumed when they finished (4 result events in the stream). The report is the last one; the earlier ones were progress notes such as "Three verifiers are back and all confirmed. I'm waiting on the other three: webh".

Everything below the line is the final message of the run, unedited.

---

# Security Review

**Mode:** full scan
**Read in depth:** 19 files: every route handler under `app/api/**` (9), `lib/auth.ts`, `lib/credits.ts`, `lib/db.ts`, `lib/ai.ts`, `lib/stripe.ts`, `lib/avatar.ts`, `db/schema.sql`, `.env.example`, `package.json`, `tsconfig.json`
**Skipped:** `README.md` (docs), `.claude/commands/*` (tooling, not app code). There are no tests or generated files.
**Candidates:** 7 found, 7 confirmed at confidence >= 8/10, 0 dropped at verification

---

## Critical (6)

### 1. Forged Stripe webhook grants any tenant unlimited credits
**File:** `app/api/webhooks/stripe/route.ts:5-16`
**Category:** Forged payment events
**Confidence:** 9/10

The handler parses the request with `req.json()` and calls `addCredits(metadata.tenantId, Number(metadata.credits))`. It never checks the `stripe-signature` header. `STRIPE_WEBHOOK_SECRET` is listed in `.env.example` but nothing reads it. The route has no session check and no middleware in front of it. The credit amount has no limit, so a negative value can also drain another tenant's balance.

**Exploit:** An attacker reads their own `tenantId` from the payload of their session JWT. The payload is base64, and anyone can view their own cookie in devtools. They then send `POST /api/webhooks/stripe` with `{"type":"checkout.session.completed","data":{"object":{"metadata":{"tenantId":"<id>","credits":"100000000"}}}}`. The upsert at `lib/credits.ts:22-28` adds the credits to their balance, so they get free AI usage paid for by the operator.

**Fix:**
```ts
// before
const event = await req.json();

// after
const sig = req.headers.get("stripe-signature");
if (!sig) return NextResponse.json({ error: "missing signature" }, { status: 400 });
let event: Stripe.Event;
try {
  event = stripe.webhooks.constructEvent(await req.text(), sig, process.env.STRIPE_WEBHOOK_SECRET!);
} catch {
  return NextResponse.json({ error: "invalid signature" }, { status: 400 });
}
```

### 2. SQL injection in invoice search
**File:** `app/api/invoices/search/route.ts:9-15`
**Category:** Injection (SQL)
**Confidence:** 9/10

`q` comes from the query string and is placed directly into `ILIKE '%${q}%'`. Only `tenant_id` is passed as a bound parameter. `lib/db.ts` is a plain `pg` Pool with no escaping, and the schema has no row-level security.

**Exploit:** Any signed-in user calls `GET /api/invoices/search?q=' UNION SELECT 1, email||':'||password_hash, 0 FROM users--`. The response contains every tenant's user emails and bcrypt hashes. The same technique reads every tenant's invoices and credit balances.

**Fix:**
```ts
// before
`... WHERE tenant_id = $1 AND customer_name ILIKE '%${q}%' ...`, [session.tenantId]

// after
`... WHERE tenant_id = $1 AND customer_name ILIKE '%' || $2 || '%' ...`, [session.tenantId, q]
```

### 3. Any tenant can read any other tenant's invoices (IDOR)
**File:** `app/api/invoices/[id]/route.ts:7-18`
**Category:** Cross-tenant access (IDOR)
**Confidence:** 9/10

`GET` loads the invoice with `WHERE id = $1` only. `DELETE` in the same file does filter on `tenant_id`, but `GET` doesn't. `invoices.id` is `SERIAL` (`db/schema.sql:17`), so ids are sequential and easy to guess.

**Exploit:** A user in tenant A requests `GET /api/invoices/1`, `/2`, `/3` and so on. Each response returns another tenant's `customer_name`, `customer_email`, `amount_cents` and `notes`.

**Fix:**
```ts
// before
"SELECT ... FROM invoices WHERE id = $1", [id]

// after
"SELECT ... FROM invoices WHERE id = $1 AND tenant_id = $2", [id, session.tenantId]
```

### 4. SSRF with full response read in invoice import
**File:** `app/api/invoices/import/route.ts:10-21`
**Category:** SSRF
**Confidence:** 9/10

The only check on the URL is `/^https?:\/\//`. The server then calls `fetch(url, { redirect: "follow" })` and returns the status, content type and up to 100 KB of the body. The attacker chooses the host, and redirects are followed, so a host check added later could be bypassed with a redirect.

**Exploit:** A signed-in user posts `{"url":"http://169.254.169.254/latest/meta-data/iam/security-credentials/<role>"}`. They can also target `http://localhost:…` or internal `10.x` services. The response hands back cloud credentials or internal service data. AWS IMDSv2 would block the metadata request (it needs a PUT for a token), but internal services can still be reached.

**Fix:**
```ts
// after: resolve the host, reject private ranges, don't follow redirects
import { lookup } from "node:dns/promises";
import ipaddr from "ipaddr.js";

const u = new URL(url);
if (u.protocol !== "https:") return NextResponse.json({ error: "invalid url" }, { status: 400 });
const addrs = await lookup(u.hostname, { all: true });
if (addrs.some((a) => ipaddr.parse(a.address).range() !== "unicast")) {
  return NextResponse.json({ error: "blocked host" }, { status: 400 });
}
const upstream = await fetch(u, { redirect: "manual" });
```
To also stop DNS rebinding, send the request through an egress proxy, or pin the IP you resolved with an undici `Agent` `connect.lookup`.

### 5. Credit check and debit can race, giving free paid LLM calls
**File:** `app/api/ai/chat/route.ts:13-28`, `lib/credits.ts:11-20`
**Category:** Billing race
**Confidence:** 9/10

The route checks `getBalance() >= 1`, then calls Anthropic, and only debits afterwards. `debit()` itself reads the balance in one statement and writes an absolute value (`SET balance = $1`) in another. There is no transaction, row lock or conditional update. The race window lasts as long as the LLM call.

**Exploit:** A tenant with 1 credit fires 50 parallel `POST /api/ai/chat` requests. All 50 pass the check and all 50 call Anthropic. The concurrent debits overwrite each other and leave the balance at 0, or throw after the paid call has already happened. The operator pays for 50 calls and the tenant paid for 1.

**Fix:**
```ts
// lib/credits.ts
export async function reserve(tenantId: string, amount: number): Promise<boolean> {
  const { rowCount } = await db.query(
    "UPDATE credit_balances SET balance = balance - $1 WHERE tenant_id = $2 AND balance >= $1",
    [amount, tenantId],
  );
  return rowCount === 1;
}
// route: call reserve() BEFORE anthropic.messages.create; return 402 if false; refund with addCredits() if the call throws.
```
Also add `CHECK (balance >= 0)` on `credit_balances.balance`.

### 6. Unauthenticated LLM endpoint where the caller picks the model and max_tokens
**File:** `app/api/ai/summarize/route.ts:5-18`
**Category:** Paid-API spend without identity
**Confidence:** 9/10

This route has no session check, no rate limit, no credit debit and no spending limit. It also passes `model` and `max_tokens` from the request body straight to `anthropic.messages.create`, using the operator's `ANTHROPIC_API_KEY`. The repo has no middleware that could protect it.

**Exploit:** An anonymous script sends `POST /api/ai/summarize {"text":"x","model":"<most expensive model>","max_tokens":<model max>}` in a loop. Every request is billed to the operator, with no upper limit.

**Fix:**
```ts
// before
model: model ?? DEFAULT_MODEL,
max_tokens: max_tokens ?? 1024,

// after
// ignore client-supplied model/max_tokens entirely
model: DEFAULT_MODEL,
max_tokens: 512,
```
Then also do one of these: require `getSession()` and debit credits the way the chat route should, or put this public demo behind a per-IP rate limit (taken from the platform's trusted client-IP header) plus a global daily spending cap. Keep `text.length` capped as well.

---

## High (1)

### 7. Stripe webhook has no idempotency, so a retried event credits twice
**File:** `app/api/webhooks/stripe/route.ts:8-12`, `lib/credits.ts:22-28`
**Category:** Payment webhook without idempotency
**Confidence:** 8/10

The handler never records `event.id` or the checkout session id, and `addCredits` adds to the existing balance. Stripe delivers events at least once and retries after timeouts or non-2xx responses. If the first delivery commits but its response is lost, the retry grants the credits a second time. Signature verification from finding 1 does not fix this.

**Exploit:** No attacker is needed. A slow response or a duplicate delivery during a normal purchase is enough for the tenant to receive the pack twice.

**Fix:**
```sql
CREATE TABLE stripe_events (id TEXT PRIMARY KEY, processed_at TIMESTAMPTZ NOT NULL DEFAULT now());
```
```ts
const client = await db.connect();
try {
  await client.query("BEGIN");
  const { rowCount } = await client.query(
    "INSERT INTO stripe_events (id) VALUES ($1) ON CONFLICT DO NOTHING", [event.id]);
  if (rowCount === 1) {
    await client.query(
      `INSERT INTO credit_balances (tenant_id, balance) VALUES ($1, $2)
       ON CONFLICT (tenant_id) DO UPDATE SET balance = credit_balances.balance + EXCLUDED.balance`,
      [tenantId, Number(credits)]);
  }
  await client.query("COMMIT");
} catch (e) { await client.query("ROLLBACK"); throw e; } finally { client.release(); }
```
Also check `event.data.object.payment_status === "paid"`. Take the credit count from your own `CREDIT_PACKS` using the line item's price id, not from metadata.

---

## Checks that passed

- **JWT handling** (`lib/auth.ts:11-24`): tokens are signed and verified with HS256, and the `algorithms` allowlist is pinned. `expiresIn: "12h"` is set and `jwt.verify` enforces it. If `JWT_SECRET` is missing, startup fails (`lib/auth.ts:7-9`).
- **Session cookie** (`app/api/auth/login/route.ts:23-29`): the cookie is `httpOnly`, `secure` and `sameSite: "lax"`, with a 12h `maxAge`. Lax blocks cross-site POST, PUT and DELETE, which covers CSRF on every state-changing JSON route here.
- **Login** (`app/api/auth/login/route.ts:12-17`): the query is parameterized, passwords are checked with bcrypt, and the same error is returned whether the email or the password is wrong.
- **Tenant scoping is correct** in `GET`/`POST /api/invoices` (`app/api/invoices/route.ts:10,29`) and in `DELETE /api/invoices/[id]` (`app/api/invoices/[id]/route.ts:26`).
- **Checkout** (`app/api/billing/checkout/route.ts`): the user must be signed in. The pack is looked up in a server-side `CREDIT_PACKS` map, and `tenantId` comes from the session, not from the client.
- **Chat route** (`app/api/ai/chat/route.ts`): the user must be signed in, the input length is capped, the model and `max_tokens` are fixed, and no tools are given to the model. Apart from the race in finding 5, it's fine.
- **`Math.random`** is used only in `lib/avatar.ts:3` for an avatar color, not for anything security-related.
- **No hardcoded secrets**: `.env.example` has only empty placeholders and a local dev DB URL, and `.env` is gitignored.
- **No unsafe sinks**: no `eval`, `child_process`, `dangerouslySetInnerHTML` or open CORS in app code.

## Not reviewed / limits

- **Git history secrets scan didn't run.** The permission prompt blocked the two `git log` commands. The repo has a single commit (`8957b0e`), and its only env file is `.env.example` with empty values. Run the two `git log` scans from the skill (section 3) to confirm.
- **Dependency CVEs weren't checked.** Run `npm audit` or `osv-scanner` against `package.json`.
- **Nothing was run against a live database or server.** Every exploit path was traced statically.
- **Deployment couldn't be checked:** whether IMDSv2 is enforced (this affects how bad finding 4 is), and whether any edge proxy or WAF sits in front of `/api/ai/summarize` or `/api/webhooks/stripe`.
- **No rate limiting on login.** That's out of scope for this rubric and wasn't reported.
- **Verification ran in 6 independent sub-agents**, one per candidate, with the two webhook candidates grouped together.
- **`README.md` and `package.json` say this repo is a deliberately vulnerable test fixture.** Findings are reported on the code as written.
