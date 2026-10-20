# Real output: `/audit-saas exec` on `examples/vulnerable-saas`

| | |
|---|---|
| Date | 2026-10-20 (run started 17:35 UTC) |
| Claude Code | 2.1.304 (`claude --version`) |
| Model | claude-opus-5-5 (every turn) |
| Kit commit | `0ab016b` (the command files as of that commit; the run recorded `dac7964`, whose hash changed when a stray bytecode file was removed from the unpublished branch history, with no other difference) |
| Invocation | `claude -p "/audit-saas exec" --model opus --setting-sources project --strict-mcp-config --output-format stream-json --verbose --max-budget-usd 25` |
| Target | a copy of `examples/vulnerable-saas` in a temporary directory, one git commit, the kit commands installed in its `.claude/commands/` |
| Reported by Claude Code | US$ 0.41 at API list prices, 63 s wall time, 6 turns, 5 Bash calls |
| Permission denials | 2 Bash calls were refused in headless mode (they were not pre-approved and nobody could answer a prompt) |

Everything below the line is the final message of the run, unedited.

---

# SaaS Audit: Invoice AI, `exec` mode

**Scope:** I read all 19 source and config files in full. There is no middleware, Dockerfile, CI, lockfile, tests or legal documents. The README and `package.json` say this is a test fixture with planted bugs. I audited it as if it were going to production anyway.

## 1. Verdicts

**Ready to operate? NO.**
- Any signed-in user can read every tenant's invoices: through SQL injection in `app/api/invoices/search/route.ts:12`, or through the IDOR in `app/api/invoices/[id]/route.ts:13`.
- Any signed-in user can make the server fetch internal URLs (SSRF, `app/api/invoices/import/route.ts:15`).
- There are no rate limits, no security headers, no RLS, no deploy setup and no lockfile.

**Can it take payments today? NO.** Stripe Checkout is wired correctly: the price id comes from the server and the success redirect grants nothing. But the webhook (`app/api/webhooks/stripe/route.ts:6`) never checks the signature or deduplicates events. Anyone can POST a fake `checkout.session.completed` with `metadata: {tenantId, credits: 999999}` and get free credits. `STRIPE_WEBHOOK_SECRET` is in `.env.example` but nothing uses it. Refunds and disputes are not handled either.

**Is the budget safe? NO.** `POST /api/ai/summarize` is public, has no rate limit, and passes `model` and `max_tokens` from the request body straight to Anthropic. Realistic worst case:
- **T0:** someone finds the landing-page endpoint.
- **T+5min:** a script sends parallel requests with the most expensive model, the largest `max_tokens` and unlimited `text`.
- **T+hours:** the Anthropic balance is drained. Nothing tracks spend, so nobody gets an alert.
- **Next morning:** every paying customer's `/api/ai/chat` fails, and their credits are still shown as available.

**Absolute minimum to ship (P0):**
1. Verify the Stripe signature over the raw body (`stripe.webhooks.constructEvent`). Add a `stripe_events(event_id UNIQUE)` table and insert into it in the same transaction as `addCredits`. Check `payment_status === 'paid'`.
2. Lock down `/api/ai/summarize`: hardcode the model, cap `max_tokens` (around 512) and `text` length, rate-limit per IP, add a captcha and a global daily ceiling. Or require a session and credits.
3. Make the debit atomic and do it before the call: `UPDATE credit_balances SET balance = balance - $1 WHERE tenant_id = $2 AND balance >= $1 RETURNING balance`. Refund in a ledger if the provider call fails.
4. Fix SQL injection in search (`ILIKE '%' || $2 || '%'`) and add `AND tenant_id = $2` to `GET /api/invoices/[id]`.
5. SSRF: allow only certain hosts, block private, loopback and link-local IPs after DNS resolution, set `redirect: "manual"`, add a timeout and a size cap, and don't reflect raw upstream bodies.
6. Add a per-tenant `usage_records` table, a daily cap per tenant, and a per-user rate limit on `/api/ai/chat` and `/api/auth/login`.

## 2. Scores 0-10

| Pillar | Score | One-line summary |
|---|---|---|
| S1 Architecture + deploy | 2 | No Dockerfile, CI, lockfile or middleware. Stripe and Anthropic keys aren't checked at startup (`lib/stripe.ts:3` falls back to `""`). No timeouts on outbound calls. |
| S2 Security | 2 | SQL injection, IDOR, SSRF, no rate limits, no security headers. Good parts: JWT locked to HS256 with an expiry, cookie set HttpOnly/Secure/SameSite, bcrypt. |
| S3 Multi-tenancy | 3 | `tenant_id` is on every table, but filtering relies on each developer remembering it. It is missing in `[id]` GET and can be bypassed through search. No RLS. |
| S4 Robustness | 3 | Provider errors aren't caught. Debit and AI call aren't in one transaction. No health check, structured logs or correlation id. |
| S5 Concurrency | 2 | The debit is a read followed by an absolute `SET`, so parallel requests overwrite each other. |
| S6 Quality | 4 | Small and readable. No tests. Credit cost is a magic number in the route. |
| S7 Performance | 6 | `(tenant_id, created_at)` index exists and lists are capped. A leading-wildcard `ILIKE` means search scans the table. |
| S8 Privacy / legal | 0 | No terms, privacy policy, DPA or data-deletion flow. Customer invoices (customer PII) are sent to Anthropic without any notice to users. |
| B1 Gateway + enforcement | 2 | Checkout is safe. The webhook is unsigned and not idempotent. No refund or dispute handling. No payment ledger. |
| B2 Unauthenticated consumption / abuse | 0 | A public LLM route where the caller picks the model and `max_tokens`. |
| B3 Cost tracking | 0 | No `usage_records`. The real `message.usage` returned by the API is thrown away. |
| B4 Caps + debit race | 1 | Balance is checked before the call (the one good point). Debit is not atomic, no daily cap, no concurrency limit. |
| B5 Provider balance + recharge | 0 | No balance check, no alerts, no runbook. |
| B6 Reconciliation / refund | 1 | No credit ledger and no refund path. If `debit` fails after the call, the AI call was free. |
| B7 Margin per customer | 0 | No admin panel or cost data. |
| **Overall SaaS / Billing** | **2.8 / 0.6** | |

## 3. Top 5 critical blockers

1. **`app/api/webhooks/stripe/route.ts:6`: CRITICAL (B1). Forged webhook gives unlimited credits.** It runs `req.json()` with no `constructEvent` and no `event_id` dedup. Exploit: `curl -X POST /api/webhooks/stripe -d '{"type":"checkout.session.completed","data":{"object":{"metadata":{"tenantId":"<own>","credits":"1000000"}}}}'`. Stripe retries also credit twice. Fix: read `await req.text()`, call `stripe.webhooks.constructEvent(raw, req.headers.get("stripe-signature"), process.env.STRIPE_WEBHOOK_SECRET)`, `INSERT INTO stripe_events(event_id) ... ON CONFLICT DO NOTHING` in the same transaction as the credit, and require `payment_status === "paid"`. Then handle `charge.refunded` and `charge.dispute.created` by taking the credits back.

2. **`app/api/ai/summarize/route.ts:6-15`: CRITICAL (B2/B4). Public open proxy to Anthropic.** There is no session check. `model` and `max_tokens` come from the body and `text` has no length limit. Any script can run the most expensive model at full output length on your key. Fix: `model: DEFAULT_MODEL` only, `max_tokens: 512`, `text.length <= 8000`. Add a per-IP rate limit (from the proxy-set IP header, not raw `X-Forwarded-For`), Turnstile or hCaptcha, and a global daily request or USD ceiling held in Redis or Postgres.

3. **`lib/credits.ts:11-19` + `app/api/ai/chat/route.ts:13,28`: CRITICAL (B4). Debit race; credit spent after the call.** The flow is check balance, call Anthropic, then `getBalance`, then `SET balance = old - 1`. Fifty parallel requests with 1 credit all pass the check, all call the provider, and the lost updates leave the balance at about 0, so you pay for 50 calls and collect 1 credit. Fix: debit up front with `UPDATE credit_balances SET balance = balance - $1 WHERE tenant_id = $2 AND balance >= $1 RETURNING balance` and treat 0 rows as 402. Use a `credit_transactions(tenant_id, delta, reason, ref_id UNIQUE)` ledger, refund on provider error, and record `message.usage` in `usage_records`. Add a daily cap and a concurrency limit per tenant.

4. **`app/api/invoices/search/route.ts:12`: CRITICAL (S2/S3). SQL injection into the query string.** `q` is placed directly into the SQL. `q = %' OR true --` returns every tenant's invoices. A `UNION SELECT email, password_hash, ...` on `users` pulls credentials. Fix: `AND customer_name ILIKE '%' || $2 || '%'` with `[session.tenantId, q]`, and escape `%`/`_` in `q`.

5. **`app/api/invoices/[id]/route.ts:13`: CRITICAL (S3). IDOR across tenants.** It runs `WHERE id = $1` with no tenant filter, and ids are sequential `SERIAL` numbers. Looping `id = 1..N` dumps every customer's name, e-mail, amount and notes. Fix: `WHERE id = $1 AND tenant_id = $2`, as DELETE already does. Longer term, add Postgres RLS or a query helper that always scopes by tenant.

Just below the top 5:
- **SSRF (HIGH):** `app/api/invoices/import/route.ts:15` fetches any URL, follows redirects and returns 100 KB of the response. It becomes CRITICAL on cloud hosts where the instance metadata service (169.254.169.254) is reachable.
- **No login rate limit:** `app/api/auth/login/route.ts`.
- **No `usage_records`, no provider balance check, no legal documents.**

## 13. Not reviewed / limits

- **SCA not run.** `npm audit`, `osv-scanner` and `trivy` were not run, and with no lockfile there is no exact dependency tree to scan. `next` 15.5.4 is pinned; the rest use caret ranges.
- **Not in the repo:** no frontend pages, `middleware.ts`, signup or password-reset flows, deploy config or CI. I can't assess CSP and headers, the landing page or a captcha. If some unseen proxy or edge layer protects `/api/ai/summarize`, finding #2 would be less severe; nothing in the repo suggests one exists.
- **Not checked:** which models the Anthropic key can access and their prices, and the credit pack prices. The prices live in the Stripe dashboard (`price_small_pack` and `price_large_pack` are placeholders), so I could not calculate the margin per pack. When you do, take Haiku 5.5's price from Anthropic's current price list, not from memory.
- **Dashboard-only:** Anthropic prepaid balance and auto-recharge, the Stripe webhook endpoint registration and secret, live vs. test keys. These go on the human checklist.
- **Runtime checks not done:** that Next.js returns no stack traces in production, cookie behaviour behind your proxy, and how DNS resolves for the SSRF.
- **Not findings:** `Math.random` in `lib/avatar.ts` only picks a UI colour. Login returns the same error message for unknown e-mails and wrong passwords; it does skip the bcrypt compare for unknown e-mails, which leaks a small timing difference (LOW).
