# gomio-claude-kit

Claude Code commands, hooks and a status line for people who build apps fast and want to know
what will break before customers find it. Free and MIT licensed.

Maintained by Gomio (https://gomio.com.br) · Pedro Gomes (https://portfolio.pgdev.com.br/en)

| Piece | What it does | Path |
|---|---|---|
| `/review-security` | Security review of pending changes, a path, or the whole repo. Every candidate finding is checked by a separate sub-agent that tries to disprove it; anything below 8/10 confidence is dropped. | `commands/review-security.md` |
| `/audit-saas` | Pre-production audit of a SaaS that charges customers and calls paid APIs: readiness (security, tenancy, robustness, privacy) plus billing and AI cost (plan enforcement, abuse, cost tracking, caps and races, provider balance, reconciliation, margin). | `commands/audit-saas.md` |
| Project scaffold | A spec-first project layout whose rules are enforced by hooks: the project state is re-injected after compaction, `references/` is write-protected, and a turn cannot end with code changed and the state file stale. | `scaffold/` |
| Status line | Directory, branch, model, effort, context used, and the 5-hour and 7-day plan limits with time to reset. | `extras/statusline.sh` |
| Usage report | Where your Claude Code usage went, by day, model, project and session, priced from a JSON file copied from Anthropic's price page. | `extras/usage.py`, `extras/prices.json` |
| `CLAUDE.md` template | Short user-level rules, each with its reason. | `templates/CLAUDE.md` |
| Installer | Installs by component, backs up what it replaces, safe to rerun. | `install.sh` |

## Sample output

From one real run of `/review-security full` on the app in `examples/vulnerable-saas`, which has
six planted vulnerabilities and some correct code as decoys. Claude Code 2.1.304,
claude-opus-5-5, US$ 1.10 at API list prices. The run found all six planted issues and reported
none of the decoys. Full report: [examples/outputs/review-security-full.md](examples/outputs/review-security-full.md).
The `/audit-saas exec` run on the same app is in
[examples/outputs/audit-saas-exec.md](examples/outputs/audit-saas-exec.md), and the answer key
in [examples/README.md](examples/README.md).

````markdown
**Mode:** full scan
[...]
**Candidates:** 7 found, 7 confirmed at confidence >= 8/10, 0 dropped at verification
[...]
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
[...]
````

Lines marked `[...]` were cut; nothing else was changed.

## Requirements

- [Claude Code](https://code.claude.com). The kit was tested with 2.1.304.
- `git`
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`), for the scans in both commands
- `jq`, for the status line and the scaffold's PreToolUse hook (which falls back to `python3`)
- `python3` 3.9 or later, for `usage.py`
- bash. The installer and hooks run on the bash 3.2 that ships with macOS.

## Install

```bash
git clone https://github.com/DevPedroGomes/gomio-claude-kit.git
cd gomio-claude-kit
bash install.sh --all --dry-run            # shows what it would write, writes nothing
bash install.sh --all                      # commands + status line + usage report
bash install.sh --scaffold ~/code/new-app  # project scaffold into a new directory
```

| Flag | Installs |
|---|---|
| `--commands` | `review-security.md` and `audit-saas.md` into `<config>/commands/` |
| `--statusline` | `statusline.sh`, `usage.py` and `prices.json` into `<config>/scripts/` |
| `--scaffold <dir>` | the contents of `scaffold/` into `<dir>`; existing files are kept unless you add `--force` |
| `--all` | `--commands` and `--statusline` |
| `--dry-run` | prints every action, changes nothing |

`<config>` is `$CLAUDE_CONFIG_DIR`, or `~/.claude` when that is not set. A file that differs from
the kit's copy is saved as `<file>.bak-<timestamp>` before it is replaced. Identical files are left
alone, so a second run changes nothing. The installer does not edit `settings.json`; it prints the
line to add.

To install by hand, copy the files in the table above to the same places.

## /review-security

```text
/review-security              pending changes: commits on this branch, uncommitted edits and new files
/review-security full         targeted scan of the whole repository
/review-security src/billing/ one area in depth
```

How it works:

1. It maps the trust boundaries (routes, Server Actions, auth, raw SQL, webhooks, uploads, outbound
   requests, money, tenant filters, LLM calls) and runs ripgrep scans for the patterns behind most
   incidents.
2. Each candidate finding goes to its own sub-agent, whose instructions are to disprove it: is the
   input really attacker-controlled, is there a guard upstream, is the code reachable. The
   sub-agent scores its confidence from 1 to 10.
3. Only findings at 8/10 or higher are reported, at three levels: Critical, High, Medium. There is
   no Low level and no hardening advice.
4. The report ends with "Checks that passed" and "Not reviewed / limits", so you can see what was
   looked at and what was not.

The verification step and the 8/10 threshold follow the approach of Anthropic's built-in
`/security-review`, whose prompt is published in
[claude-code-security-review](https://github.com/anthropics/claude-code-security-review). That
command reviews the changes on the current branch. This one adds the `full` and path modes, categories for cross-tenant access, billing races, paid-API spend
without identity and LLMs with tools, and the two closing sections.

Section 5 of the command, "Project conventions", is empty on purpose. Add your own rules there (for
example "credits are debited only through `consume_credits()`") and a deviation becomes a finding
in your codebase.

Permissions: the command pre-approves only two git lookups. Claude Code already runs plain
read-only commands (`rg`, `grep`, `git diff`, `git log`, `ls`) without asking and asks before
anything else. A broad rule such as `Bash(rg:*)` would also approve `rg --pre <program>`, which
runs a program on every file it searches; in a test with Claude Code 2.1.304 that command required
approval. The repository under review is treated as untrusted input.

## /audit-saas

```text
/audit-saas                   full audit, all pillars and the full report
/audit-saas exec              verdicts, scores, top 5 blockers, limits
/audit-saas only=billing      billing and cost pillars only
/audit-saas pillars=S2,B4     selected pillars
```

The report opens with three answers: is it ready to operate, can it take payments today, and is
the budget safe if a customer pays today and comes back in three days. It is gateway-neutral (the
billing section names Stripe events as an example) and the privacy section applies to whatever law
covers you (GDPR, LGPD, CCPA). Scores and severities are the model's judgment, so two runs on the
same code can score differently.

## Project scaffold

`bash install.sh --scaffold <dir>` creates a project where Claude Code works from `specs/` and
`tasks/`, with `/init-project` to turn a brief in `references/` into specs and tasks, and
`/next-task` to run one implement-test-verify loop. Details in [scaffold/README.md](scaffold/README.md).

What enforces the rules:

| Hook or script | Behavior |
|---|---|
| SessionStart | Prints `.agent/state.md`, the active tasks and the project phase on startup, resume, `/clear` and after compaction. |
| PreToolUse on Write, Edit, NotebookEdit | Blocks writes under `references/`, including `..` paths, different letter case and symlinked roots. |
| Stop | Blocks the end of a turn once when project files are newer than `.agent/state.md`. |
| `scripts/verify.sh` | Exits 1 until you configure it. |

`tests/hooks.sh` runs each hook with the JSON Claude Code sends (33 cases). The hooks were also
checked live in Claude Code 2.1.304: the injected state was quoted back, a Write into
`references/` was refused with the hook's message, and after a file was created the Stop hook made
the session update `.agent/state.md` before it ended.

The PreToolUse hook only sees file tools. A shell command such as `sed -i` can still write into
`references/`.

## Status line and usage report

Add to `~/.claude/settings.json` (the installer prints the exact path):

```json
"statusLine": { "type": "command", "command": "/Users/you/.claude/scripts/statusline.sh" }
```

It shows `dir branch* | Opus.high | ctx 42% | 5h 23% ↻3h | 7d 41% ↻4d`. The plan limits appear on
Pro and Max plans after the first response of a session. Color thresholds can be changed with
`STATUSLINE_CTX_WARN`, `STATUSLINE_CTX_CRIT`, `STATUSLINE_LIMIT_WARN` and `STATUSLINE_LIMIT_CRIT`.

```bash
python3 ~/.claude/scripts/usage.py                    # last 7 days
python3 ~/.claude/scripts/usage.py --days 30 --sessions
python3 ~/.claude/scripts/usage.py --all --json
python3 ~/.claude/scripts/usage.py --daily-target 50 --tz America/New_York
```

`usage.py` reads the session logs under `<config>/projects` and sends nothing anywhere. Prices
come from `prices.json`, copied on 2026-10-20 from
https://platform.claude.com/docs/en/about-claude/pricing, with 5-minute and 1-hour cache writes,
cache reads, Haiku 5.5 long-context prices, fast mode and US-only inference. A model is matched by
family, so `claude-haiku-4-5-20251001`, `claude-opus-5-5[1m]` and Bedrock or Vertex spellings
find their entry, while an unknown version such as `claude-opus-5-6` stays unknown. Requests for a
model without a price are counted and reported as "N requests without a known price", never added
as $0. On a Pro or Max plan you do not pay these amounts; read them as a relative measure of usage.

## CLAUDE.md template

[templates/CLAUDE.md](templates/CLAUDE.md) is about 60 lines: commit hygiene (with tool attribution
as an explicit choice), Python only in virtual environments, delegating wide reads to subagents,
documentation through an MCP server before web search, verifying before saying done, and code
quality rules. Each rule states its reason. Copy it to `~/.claude/CLAUDE.md` and edit it.

For prose that reads like a person wrote it (READMEs, PR descriptions), the third-party
[humanizer](https://github.com/blader/humanizer) skill works well with Claude Code.

## Limits

- Both commands read code. They run no exploit and send no request to your app. They do not
  replace a penetration test or a dependency scanner (`npm audit`, `pip-audit`, `osv-scanner`).
- Model output varies between runs. Treat a finding as a lead with evidence, and confirm it before
  you act on it.
- The example runs cover one small app. A large codebase gets a sampled review, and the
  "Not reviewed" section says what was left out.
- `prices.json` holds Anthropic's first-party list prices. Edit it when prices change; Bedrock and
  Vertex prices differ.

## Tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py'   # usage.py and the scan patterns
bash tests/hooks.sh                                      # scaffold hooks and verify.sh
bash tests/statusline.sh
/bin/bash tests/install.sh                               # installer, under bash 3.2 on macOS
```

CI runs them on Linux and macOS, plus shellcheck on every script.

## License

MIT. See [LICENSE](LICENSE).
