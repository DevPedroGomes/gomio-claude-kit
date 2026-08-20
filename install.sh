#!/usr/bin/env bash
# Claude Production Kit - copies files into ~/.claude. Idempotent.
# Usage: bash install.sh [--dry-run]
set -euo pipefail

DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"

short() { printf '%s' "${1/#$HOME/~}"; }

copy() {
  local from="$1" to="$2" stamp
  if [[ ! -f "$from" ]]; then
    printf '  skip (missing): %s\n' "$(short "$from")"
    return 0
  fi
  if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
    printf '  unchanged: %s\n' "$(short "$to")"
    return 0
  fi
  if [[ -f "$to" ]]; then
    stamp="$(date +%Y%m%d%H%M%S)"
    if [[ $DRY -eq 1 ]]; then
      printf '  would back up: %s -> %s.bak-%s\n' "$(short "$to")" "$(short "$to")" "$stamp"
    else
      cp "$to" "$to.bak-$stamp"
      printf '  backed up: %s.bak-%s\n' "$(short "$to")" "$stamp"
    fi
  fi
  if [[ $DRY -eq 1 ]]; then
    printf '  would write: %s\n' "$(short "$to")"
  else
    mkdir -p "$(dirname "$to")"
    cp "$from" "$to"
    printf '  wrote: %s\n' "$(short "$to")"
  fi
}

printf '\nClaude Production Kit -> %s\n' "$(short "$DEST")"
if [[ $DRY -eq 1 ]]; then printf '(dry run: nothing will be written)\n'; fi

printf '\ncommands:\n'
copy "$SRC/commands/review-security.md" "$DEST/commands/review-security.md"

printf '\nextras (optional, referenced from settings.json):\n'
copy "$SRC/extras/statusline.sh" "$DEST/scripts/statusline.sh"
copy "$SRC/extras/usage.py"      "$DEST/scripts/usage.py"
if [[ $DRY -eq 0 && -f "$DEST/scripts/statusline.sh" ]]; then
  chmod +x "$DEST/scripts/statusline.sh"
fi

printf '\n'
if [[ $DRY -eq 1 ]]; then
  printf 'Dry run complete. Re-run without --dry-run to apply.\n\n'
else
  printf 'Done. Try /review-security in any repo.\n'
  printf 'For the status line, add to ~/.claude/settings.json:\n'
  printf '  "statusLine": { "type": "command", "command": "~/.claude/scripts/statusline.sh" }\n\n'
fi
