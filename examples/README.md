# Examples

`vulnerable-saas/` is a small multi-tenant SaaS written to test the two commands. It has six
planted vulnerabilities next to code that is correct, so a review can be judged both on what it
misses and on what it invents. **Do not deploy it.**

`outputs/` holds the real output of one headless run of each command on a copy of that app. The
header of each file records the date, the Claude Code version, the model, the kit commit and the
exact invocation. The report text is unedited.

## Answer key

| # | Planted issue | Where | `/review-security full` | `/audit-saas exec` |
|---|---|---|---|---|
| 1 | SQL built by string interpolation (`q` inside `ILIKE`) | `app/api/invoices/search/route.ts` | Critical 2 | Top blocker 4 |
| 2 | Cross-tenant read: `GET` loads an invoice by sequential id with no tenant filter | `app/api/invoices/[id]/route.ts` | Critical 3 | Top blocker 5 |
| 3 | SSRF: server fetches any `http(s)` URL, follows redirects, returns the body | `app/api/invoices/import/route.ts` | Critical 4 | Listed as HIGH under the top 5 |
| 4 | Public LLM endpoint where the caller picks `model` and `max_tokens`, no auth, no ceiling | `app/api/ai/summarize/route.ts` | Critical 6 | Top blocker 2 |
| 5 | Payment webhook with no signature check and no idempotency | `app/api/webhooks/stripe/route.ts` | Critical 1, High 7 | Top blocker 1 |
| 6 | Credit race: balance checked before the paid call, debited after, read-modify-write | `app/api/ai/chat/route.ts`, `lib/credits.ts` | Critical 5 | Top blocker 3 |

Correct code that a review should leave alone, and how the runs treated it:

| Decoy | Where | Result |
|---|---|---|
| `Math.random()` for an avatar color | `lib/avatar.ts` | Both runs said it is not a finding |
| `DELETE` with the tenant filter that `GET` lacks | `app/api/invoices/[id]/route.ts` | Listed under "Checks that passed" |
| JWT verified with a pinned algorithm and expiry | `lib/auth.ts` | Listed under "Checks that passed" |
| Checkout price taken from a server-side map | `app/api/billing/checkout/route.ts` | Listed under "Checks that passed" |

## What these runs do not prove

- One run per command on one small app. Model output varies between runs, and a 19-file app is
  far easier than a real codebase.
- The app's `README.md` and `package.json` say it contains planted vulnerabilities (both reports
  mention this). That tells the reviewer bugs exist, not where they are.
- In the security review, the git-history scan did not run: four Bash calls were refused because
  the run was headless and they were chained (`;`) or used `git -C`, which Claude Code does not
  treat as read-only. The commands were changed after this run to ask for one plain git command
  per call. That change has not been re-run yet.
