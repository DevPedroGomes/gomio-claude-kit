# Claude Production Kit

**Your app was built fast. This tells you what will break when real users hit it.**

If some of your codebase came out of Claude Code, Cursor, Lovable or v0, you already know the
uncomfortable part: it runs, the demo works, and nobody on the team can honestly say whether the
auth is right, whether one customer can read another customer's data, or whether a bad afternoon
turns into a support incident.

This is the free, shallow version of the review I do for that. One command, no signup, no
dependencies. It reads your code and comes back with specific problems, in specific files, with
the fix.

---

## What you get back

Not a checklist. Findings that name the file, the line, the exploit and the correction:

```
# Security Review
Mode: full scan
Files analyzed: 34    Files skipped: 61 (config, tests, generated)

## Critical (2)

### 1. Any signed-in user can read another workspace's invoices
File: src/api/invoices/route.ts:41-58
Category: Multi-tenant IDOR

The handler filters by `invoiceId` from the URL, but never by the workspace the
signed-in user belongs to. Session is validated, ownership is not.

Why it matters:
A customer who knows or guesses another invoice id gets the full record back:
amount, buyer name, billing email. No special access needed - a normal logged-in
account is enough. This is the failure that ends up in a disclosure email.

Suggested fix:
  // Before
  const invoice = await db.invoice.findUnique({ where: { id } })

  // After
  const invoice = await db.invoice.findFirst({
    where: { id, workspaceId: session.workspaceId }
  })

### 2. Stripe webhook accepts unsigned requests
File: src/api/webhooks/stripe/route.ts:12
...

## Checks that passed
Password hashing (bcrypt, 12 rounds) · CSRF tokens on mutations · No secrets in
git history · File upload validates magic bytes

## Not reviewed / limits
Two background workers were not read (no entry point found from the routes).
Dependency CVEs would need an SCA tool - not covered here.
```

That last section matters as much as the findings. A review that claims full coverage it did
not have is worse than no review.

---

## Why it finds things a generic prompt misses

**It reads trust boundaries, not files.** Routes, auth middleware, raw queries, webhooks,
uploads, crypto, payments, tenant filters. It skips config, generated code and type
definitions on purpose. That is how an experienced reviewer spends attention, and it is why
this still works on a codebase far larger than any model's context window.

**It searches before it reads.** A dozen targeted scans for the patterns that actually cause
incidents - SQL built by string interpolation, JWTs decoded without verifying the signature,
`verify=False`, reused encryption IVs, a spoofable header used as identity, queries missing a
tenant filter - and only then reads the hits in depth.

**It is instructed not to inflate.** Show the exploit rather than the theory. Suggest real
code, never "consider using a secure library". Never promote a Low finding to look more useful.
Never invent a vulnerability - one false positive destroys trust in the entire review.

---

## Try it

```bash
git clone https://github.com/DevPedroGomes/claude-production-kit.git
cd claude-production-kit
bash install.sh --dry-run   # shows exactly what it would write, changes nothing
bash install.sh
```

Or just copy the one file - that is all the installer does:

```bash
cp commands/review-security.md ~/.claude/commands/
```

Then, in your repo:

```
/review-security              # only what is about to merge
/review-security full         # targeted scan of the whole codebase
/review-security src/auth/    # one area, in depth
```

Two extras are in `extras/`, because they are what I keep open all day: a status line showing
model, context used and how much of your usage limit is left, and a script that reports where
that usage actually went, by day, project and session. Both run locally and send nothing
anywhere.

---

## What this does not cover

This command finds security defects. It does not tell you whether the architecture holds, what
the thing will cost you at 10x the traffic, whether your plan limits are actually enforced, or
which parts are cheaper to rebuild than to repair.

That is the deeper review: ten areas, ending in a keep / fix / rebuild verdict per area, a
phased plan and an estimate. It is a paid, fixed-fee engagement of about a week, and it is how
most of my client work starts. If the sample output above is the level you need on your own
codebase, that is the version to ask for.

---

## Who is behind it

I build phone agents that answer the calls a team cannot get to and write what happened into the
system that team already runs on. Everything I ship runs on infrastructure I manage myself, and
I use Claude Code all day - reading every line before it merges, writing the parts that touch
money or customer records by hand.

A growing share of my work is taking applications that were generated quickly and making them
safe to put a team on. This command is the first hour of that job, given away.

**Want the full review, or an agent that talks to your customers without inventing things?**
Open an issue here, or find me on Upwork.

---

MIT licensed. Use it, fork it, sell what it produces. Attribution appreciated, not required.
