#!/usr/bin/env bash
#
# SessionStart hook (startup, resume, clear, compact).
#
# Prints the durable project state so Claude Code adds it to the context at
# session start and, more importantly, after compaction. Without it, a
# compacted session silently loses track of the current task.
#
# Plain stdout from a SessionStart hook is added to Claude's context, so this
# script needs no jq. Output is capped to stay under the hook output limit.

set -uo pipefail

cat >/dev/null 2>&1 || true   # consume the JSON payload; nothing in it is needed

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE="$ROOT/.agent/state.md"
MAX_STATE_BYTES=8000

echo "# Durable project state (.agent/state.md)"
echo
if [ -f "$STATE" ]; then
  size=$(wc -c < "$STATE" | tr -d ' ')
  head -c "$MAX_STATE_BYTES" "$STATE"
  echo
  if [ "$size" -gt "$MAX_STATE_BYTES" ]; then
    echo
    echo "[state.md is $size bytes; only the first $MAX_STATE_BYTES are shown. Trim it.]"
  fi
else
  echo ".agent/state.md is missing. Recreate it before implementing."
fi

echo
echo "# Active tasks (tasks/active/)"
echo
found=0
if [ -d "$ROOT/tasks/active" ]; then
  for f in "$ROOT"/tasks/active/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    [ "$name" = "_template.md" ] && continue
    echo "- $name"
    found=1
  done
fi
[ "$found" -eq 0 ] && echo "(none)"

has_refs=0
if [ -d "$ROOT/references" ]; then
  for f in "$ROOT"/references/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in README.md|.gitkeep) continue ;; esac
    has_refs=1
    break
  done
fi

has_specs=0
for f in "$ROOT"/specs/*.md "$ROOT"/specs/*/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in README.md|_template.md) continue ;; esac
  has_specs=1
  break
done

echo
echo "# Phase"
echo
if [ "$has_refs" -eq 1 ] && [ "$has_specs" -eq 0 ]; then
  echo "references/ has source material and specs/ is still empty."
  echo "This project is NOT initialized. Run /init-project before writing any application code."
elif [ "$has_refs" -eq 0 ] && [ "$has_specs" -eq 0 ]; then
  echo "Empty scaffold: no reference material and no specs yet."
else
  echo "Project is initialized. Implementation work goes through /next-task."
fi

exit 0
