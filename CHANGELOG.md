# Changelog

## 0.2.0 (2026-10-20)

First public layout of the kit, renamed from `claude-production-kit` to `gomio-claude-kit`.

### Added

- `/audit-saas`: pre-production audit of SaaS readiness, billing and AI cost, in English and
  gateway-neutral.
- `scaffold/`: spec-first project template with SessionStart, PreToolUse and Stop hooks,
  `scripts/verify.sh` that fails until configured, `/init-project`, `/next-task` and a
  `task-verifier` subagent.
- `extras/prices.json`: model prices from Anthropic's pricing page, with source URL and date.
- `templates/CLAUDE.md`: short user-level rules, each with its reason.
- `examples/vulnerable-saas` with six planted vulnerabilities, the answer key, and real outputs of
  both commands.
- Tests for the hooks, the status line, `usage.py`, the installer and the search patterns, and a
  CI workflow that runs them on Linux and macOS with shellcheck.

### Changed

- `/review-security` verifies every candidate in a sub-agent and drops anything below 8/10
  confidence; the Low level is gone; the default mode includes uncommitted and untracked changes;
  the project conventions block is an empty template.
- `/review-security` no longer pre-approves `find`, `cat`, `rg` or git subcommands; Claude Code's
  own read-only checks cover the plain forms.
- `extras/statusline.sh`: English labels, gateway spend limit, a notice when `jq` is missing.
- `extras/usage.py`: English flags, local time zone by default, no built-in daily target, prices
  from `prices.json` matched by model family, unpriced requests reported instead of counted as $0,
  `--days 0` rejected.
- `install.sh`: installs by component, honors `CLAUDE_CONFIG_DIR`, creates missing directories,
  backs up what it replaces, and runs on bash 3.2.
- README rewritten; the sample output is now a real run.

### Fixed

- `-ttsx` in three ripgrep scans (`tsx` is not a ripgrep type, so those scans aborted).
- The weak-crypto scan matched "description" and "includes".
- The default review mode returned an empty diff on the base branch.

## 0.1.0 (2026-08-20)

- `/review-security`, status line and usage report (private).
