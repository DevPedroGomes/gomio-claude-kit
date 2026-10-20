#!/usr/bin/env bash
#
# Stop hook.
#
# CLAUDE.md says .agent/state.md must reflect reality at the end of every
# iteration. Prose cannot enforce that; this can. If project files changed
# after the last state.md update, the end of the turn is blocked once with a
# reminder (exit 2 sends stderr to Claude and keeps the turn going).
#
# It never blocks twice in a row: when Claude is already continuing because of
# a stop hook, the payload carries "stop_hook_active": true and this exits 0.

set -uo pipefail

payload=$(cat)

if printf '%s' "$payload" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE="$ROOT/.agent/state.md"

# No state file: the SessionStart hook already asks for it to be recreated.
[ -f "$STATE" ] || exit 0

newer=""
count=0

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Tracked files plus untracked files that are not ignored. Build output and
  # dependencies listed in .gitignore never trigger the hook.
  while IFS= read -r rel; do
    case "$rel" in
      .agent/*|references/*|.claude/settings.local.json) continue ;;
    esac
    if [ -f "$ROOT/$rel" ] && [ "$ROOT/$rel" -nt "$STATE" ]; then
      count=$((count + 1))
      [ "$count" -le 5 ] && newer="$newer  - $rel
"
    fi
  done <<EOF_FILES
$(git -C "$ROOT" ls-files --cached --others --exclude-standard 2>/dev/null)
EOF_FILES
else
  while IFS= read -r abs; do
    [ -z "$abs" ] && continue
    count=$((count + 1))
    [ "$count" -le 5 ] && newer="$newer  - ${abs#"$ROOT"/}
"
  done <<EOF_FILES
$(find "$ROOT" \
    \( -path "$ROOT/.git" -o -path "$ROOT/.agent" -o -path "$ROOT/references" \
       -o -name node_modules -o -name .venv -o -name venv -o -name dist -o -name build \
       -o -name .next -o -name __pycache__ -o -name .pytest_cache -o -name .ruff_cache \
       -o -name .mypy_cache -o -name coverage \) -prune -o \
    -type f ! -name '.DS_Store' ! -path "$ROOT/.claude/settings.local.json" \
    -newer "$STATE" -print 2>/dev/null)
EOF_FILES
fi

[ "$count" -eq 0 ] && exit 0

{
  echo "$count file(s) changed after the last .agent/state.md update, for example:"
  printf '%s' "$newer"
  echo
  echo "Before finishing, update the durable state:"
  echo "  - .agent/state.md     current task, phase, blockers, next action, last verification"
  echo "  - .agent/progress.md  one short line for what this iteration changed"
  echo "  - .agent/decisions/   a new record if a durable decision was made"
  echo
  echo "If the work is unfinished, record that as the state. Do not skip it."
} >&2

exit 2
