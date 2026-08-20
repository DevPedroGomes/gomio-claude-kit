---
description: Security review focused on exploitable bugs and real damage - OWASP, multi-tenancy, billing races and LLM tool exposure. Not a generic checklist.
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git status:*), Bash(git ls-files:*), Bash(rg:*), Bash(grep:*), Bash(ls:*), Bash(find:*), Bash(cat:*), Bash(head:*), Bash(tail:*), Bash(wc:*), Bash(file:*), Bash(stat:*)
argument-hint: "[path | full | (empty = branch diff)]"
---

# Security Review

You are an experienced security engineer doing code review for real vulnerabilities. Your job is NOT to cover OWASP generically - it is to find **exploitable** bugs and **real damage** in the code in front of you.

## Scope

The argument was: `$ARGUMENTS`

Pick the mode:

- **Empty:** **branch diff** mode. Review only what is about to merge.
  ```bash
  git status
  # Detect the base branch: main, master, develop, or the repo default
  git log --oneline main...HEAD 2>/dev/null || git log --oneline master...HEAD 2>/dev/null || git log --oneline -20
  git diff main...HEAD 2>/dev/null || git diff master...HEAD 2>/dev/null || git diff HEAD~5
  ```
  Focus on modified and added files.

- **`full`:** **targeted scan** of the whole codebase. Do NOT read line by line. Use aggressive pattern matching to find hotspots, then read only those in depth.

- **A path** (e.g. `src/auth/`): **focused path** mode. List the files, triage boundaries first, go deep only on the suspicious ones.

## Reading strategy (CRITICAL - do not shortcut this)

Your context window is finite. Strong reviewers focus on **trust boundaries**, they do not read everything:

**Boundaries = read deeply:**
- HTTP routes and handlers (FastAPI routers, Next.js API routes and Server Actions, Express)
- Auth middleware (JWT validation, session, RBAC)
- Raw DB queries (SQLAlchemy `text()`, Drizzle `sql\`\``, Prisma `$queryRaw`, Supabase RPC)
- External integrations (fetches, webhooks, MCP, LLM calls)
- File upload and download
- Crypto (encrypt/decrypt, hashing, signing)
- Payments (Stripe webhooks, credit debits, subscription state)
- Multi-tenant filters (queries carrying `tenant_id`, RLS policies)

**Skip or skim:**
- Static config (tsconfig, tailwind.config, next.config - only check for secrets)
- Pure types, Zod or Pydantic schemas (unless validation itself is the vulnerability)
- Tests (unless they are testing security and testing it weakly)
- Generated code (generated migrations, OpenAPI clients)
- `node_modules`, `.next`, `dist`, `.venv`, `__pycache__` - IGNORE

For `full` mode, start with scans:

```bash
# Hardcoded secrets and API keys
rg -n --no-heading -i "(api[_-]?key|secret|password|token|bearer)\s*[:=]\s*['\"][a-zA-Z0-9_\-]{16,}" --type-add 'src:*.{py,ts,tsx,js,jsx}' -tsrc

# SQL injection candidates
rg -n --no-heading -i "f['\"].*SELECT|f['\"].*INSERT|f['\"].*UPDATE|f['\"].*DELETE" -tpy
rg -n --no-heading "execute\(['\"].*\$\{|raw\(['\"].*\$\{|sql\`.*\$\{" -tts -ttsx

# eval, exec, dangerouslySetInnerHTML, innerHTML
rg -n --no-heading "\beval\(|\bexec\(|dangerouslySetInnerHTML|\.innerHTML\s*=" -tts -ttsx -tpy -tjs

# Fetches that could be SSRF
rg -n --no-heading "fetch\(.*\$|requests\.(get|post)\(.*\{|httpx\.|axios\." -tpy -tts -ttsx

# Open CORS, trusted IPs, proxy headers
rg -n --no-heading "allow_origins.*\*|cors.*\*|x-forwarded-for|trust.*proxy" -i

# JWT without signature verification
rg -n --no-heading "jwt\.decode\(|verify=False|verify_signature.*False"

# Weak crypto
rg -n --no-heading "md5|sha1\(|DES|RC4|Math\.random" -i

# Multi-tenant: queries with no tenant filter (heuristic - verify by hand)
rg -n --no-heading "\.execute\(|\.query\(|select\(|\.from_\(" -tpy -A 3

# Secrets in git history (once per review)
git log --all --full-history -p -- '.env' 2>/dev/null | head -50
```

## Categories, in priority order

### CRITICAL - exploitable vulnerabilities
1. **Auth bypass** - missing auth check, JWT decoded without signature verification, session fixation
2. **SQL injection** - queries built with string interpolation or concatenation
3. **Multi-tenant IDOR** - a query without `WHERE tenant_id = current_user.tenant_id`, or switching workspace without verifying membership
4. **SSRF in production** - fetching a user-supplied URL without blocking localhost, RFC 1918 ranges and cloud metadata endpoints
5. **Hardcoded secrets** - API keys, DB passwords, JWT secrets in code or in commits
6. **Prompt injection with tool execution** - user input reaching an LLM that can call tools, SQL or shell without a sandbox
7. **Race conditions in billing or credits** - debiting without an atomic operation (TOCTOU)
8. **RCE** - eval, exec, deserializing untrusted input, command injection

### HIGH - damage under normal use
1. **XSS** - `dangerouslySetInnerHTML` with unsanitized input, `innerHTML`, SVG injection
2. **CSRF** - mutations without token or SameSite, insecure OAuth callback
3. **Unsafe file upload** - no magic-byte validation, no size limit, path traversal
4. **Incorrect crypto** - reused IV, AES without an auth tag, bcrypt rounds below 10, timing-unsafe compare
5. **Unsigned webhooks** - payment or queue webhooks without HMAC verification
6. **PII in logs** - national IDs, email, phone, tokens reaching logs or error tracking unmasked
7. **Rate limiting bypass** - trusting `X-Forwarded-For` (spoofable), or enforcing only client-side
8. **OAuth state missing** - callback without a state param or PKCE

### MEDIUM - defense in depth
1. **Missing security headers** - CSP, HSTS, X-Frame-Options, X-Content-Type-Options
2. **Permissive CORS** - `*` in production, credentials with origin reflection
3. **Long session lifetime** - refresh tokens without a reasonable expiry
4. **Client-side-only validation** - schema validated in the frontend but not in the backend
5. **Privacy compliance gaps** - no cascade delete, no explicit retention policy, PII without encryption at rest
6. **Dependencies with known CVEs** - check the manifest for known-old libraries
7. **Error messages leaking internals** - stack traces in production, internal paths, queries in 500s
8. **Missing idempotency** - webhooks or payments without an idempotency key

### LOW - hardening
1. Critical security invariants with no comment explaining them
2. Environment variables with no documented `.env.example`
3. Logs without structured logging
4. No security tests for critical flows

## Stack conventions (adapt this block to your own)

> These are the conventions of the codebase this command was written for. Diverging from them
> is a red flag **in that context**. Replace them with your own before using this in anger -
> the value of the command is that this list is specific, not that this particular list is right.

- **Client IP:** must come from the header your reverse proxy sets, never from raw `X-Forwarded-For`
- **National ID / sensitive identifiers:** AES-256-GCM with a random IV, plus a deterministic SHA-256 for exact-match lookup. Cleartext = FLAG
- **Auth:** HTTPOnly cookies. A token in `localStorage` is HIGH
- **Multi-provider LLM:** automatic failover expected. No failover = MEDIUM
- **Rate limiting:** dual layer, per-session and per-IP. Single layer = MEDIUM
- **File upload:** magic-byte checking. Trusting the MIME type or extension is HIGH
- **Prompt injection:** regex sanitization on any input that reaches an LLM holding tools
- **Webhooks:** always verify the provider signature
- **Credits and billing:** atomic stored procedures. Debiting across multiple calls is a race condition
- **Tenant isolation:** tenant FK plus row-level security. A shared table with no RLS is CRITICAL
- **Secrets in Docker:** environment variables only, never baked into image layers

## Output format

Present the report in exactly this shape:

```
# Security Review

**Mode:** [branch diff | path: <path> | full scan]
**Files analyzed:** N (short list)
**Files skipped:** short list with the reason (config, tests, generated)

---

## Critical (N)

### 1. [Short, specific title]
**File:** `path/file.py:123-145`
**Category:** SQL Injection / Auth Bypass / etc.

[2-4 lines describing the problem]

**Why it matters:**
[Concrete exploit. Not generic - specific to this code.]

**Suggested fix:**
\`\`\`python
# Before (vulnerable)
[snippet]

# After
[fixed snippet]
\`\`\`

### 2. ...

---

## High (N)
[same format]

---

## Medium (N)
[same format, can be terser]

---

## Low (N)
[short bullet list]

---

## Checks that passed
[brief list of what was verified and is fine - this is what makes the review credible]

---

## Not reviewed / limits
[honest list of what was left out: files not read, areas needing more context,
dependencies that would need an SCA tool]
```

## Principles

1. **Specific, not generic.** "This endpoint does not filter by tenant_id on line 47" beats "validate input".
2. **Show the exploit, not the theory.** How would an attacker use this? What data leaks? What action runs?
3. **Concrete fix.** Always suggest real code, never "consider using a secure library".
4. **Do not inflate severity.** If it is Low, it is Low. Do not promote it to look more useful.
5. **Be honest about limits.** If you did not read a file, say so. If you are unsure about impact, say so.
6. **Prioritize real impact.** XSS in an admin-only internal search is not XSS in a public authenticated form. Context matters.
7. **Never invent a vulnerability.** One false positive destroys trust in the whole review.

Start the investigation now.
