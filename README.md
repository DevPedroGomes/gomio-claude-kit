# Claude Production Kit

Claude Code writes code fast. It does not tell you whether that code is safe to put in front
of paying users.

This is the part of my setup that closes that gap: a security review command that hunts for
**exploitable** bugs instead of reciting OWASP, plus the two scripts I actually keep open all
day - a status line that shows how much of my usage limit is left, and a local report of where
that usage went.

No dependencies. No account. Copy two files and it works.

---

## Install

```bash
git clone https://github.com/DevPedroGomes/claude-production-kit.git
cd claude-production-kit
bash install.sh --dry-run   # shows exactly what it would write
bash install.sh
```

Or skip the script entirely - it only copies files:

```bash
cp commands/review-security.md ~/.claude/commands/
```

Then, in any repo:

```
/review-security              # reviews only what is about to merge
/review-security full         # targeted scan of the whole codebase
/review-security src/auth/    # one path, in depth
```

---

## What is in here

### `commands/review-security.md`

A security review that behaves like a reviewer with a finite context window, because it has one.

Three things make it different from asking "review my code for security issues":

**It reads boundaries, not files.** Routes, auth middleware, raw queries, webhooks, uploads,
crypto, payments, tenant filters. It explicitly skips config, generated code and pure type
definitions. That is how a real reviewer spends attention, and it is why the review still works
on a codebase that does not fit in context.

**It starts with ripgrep, not with reading.** A dozen scans for the patterns that actually
produce incidents - string-interpolated SQL, `jwt.decode` without verification, `verify=False`,
reused IVs, `X-Forwarded-For` used as an identity, queries with no tenant filter - and only then
reads the hits in depth.

**It is told not to inflate.** Explicit instructions: show the exploit rather than the theory,
suggest real code rather than "consider a secure library", never promote a Low to look useful,
and list what was *not* reviewed. One false positive destroys trust in a whole review, so the
command says so out loud.

It also carries a **stack conventions** block - a list of the specific invariants of one codebase
(where the client IP comes from, how sensitive identifiers are stored, how credits are debited).
Replace that block with your own. The value is that the list is specific to a codebase, not that
my list is right for yours.

### `extras/statusline.sh`

Status line showing directory, git branch, model and reasoning effort, context used, and how
much of the 5-hour and weekly limits is gone. Point `settings.json` at it:

```json
{ "statusLine": { "type": "command", "command": "~/.claude/scripts/statusline.sh" } }
```

### `extras/usage.py`

Reads `~/.claude/projects/*.jsonl` and reports where the week went - by day, model, project and
session. Runs locally, sends nothing anywhere.

```bash
python3 extras/usage.py          # current week
```

---

## What is deliberately not in here

**The full production audit.** There is a longer command behind this one - ten pillars covering
architecture, plan enforcement, cost, multi-tenancy, concurrency, performance and data
protection, ending in a keep / fix / rebuild verdict per area. That one is how I do paid
assessments, so it is not in the box. If that is what you actually need, see below.

**My global `CLAUDE.md`, MCP config and project skills.** They contain server addresses,
client project names and personal paths. Nobody else's dotfiles are useful anyway - what
transfers is the method, not my file layout.

---

## Who wrote this

I build phone agents that answer the calls a team cannot get to and write what happened into the
system that team already runs on - and I do it with Claude Code in front of me all day, reading
every line before it merges.

A large share of that work now is repairing applications that were generated quickly and then
had to survive real users: auth and permissions redone properly, the data layer reviewed, an
honest verdict on what to keep and what to rebuild. This command is the shallow, free version
of the first hour of that job.

If you want the deep version on your codebase, or an agent that talks to your customers without
inventing things, open an issue or reach me on Upwork.

---

## License

MIT. Use it, fork it, sell the output of it. Attribution appreciated, not required.
