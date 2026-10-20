#!/usr/bin/env bash
#
# gomio-claude-kit installer. Copies kit files into place; changes nothing else.
#
#   bash install.sh --commands             /review-security and /audit-saas, user level
#   bash install.sh --statusline           status line and usage report scripts
#   bash install.sh --scaffold <dir>       project scaffold into <dir>
#   bash install.sh --all                  --commands and --statusline
#   bash install.sh --all --dry-run        show what would happen, write nothing
#
# User-level files go to $CLAUDE_CONFIG_DIR, or ~/.claude when it is not set.
# An existing file that differs is backed up as <file>.bak-<timestamp> first.
# Running it twice is safe: identical files are left alone. In a scaffold
# target, files that already exist are kept unless you pass --force.
#
# Works with the bash 3.2 that ships with macOS.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d%H%M%S)"

DRY=0
FORCE=0
DO_COMMANDS=0
DO_STATUSLINE=0
SCAFFOLD_DIR=""

usage() {
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -eq 0 ]; then
  usage
  exit 2
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --commands) DO_COMMANDS=1 ;;
    --statusline) DO_STATUSLINE=1 ;;
    --all) DO_COMMANDS=1; DO_STATUSLINE=1 ;;
    --scaffold)
      if [ $# -lt 2 ] || [ -z "$2" ] || [ "${2#--}" != "$2" ]; then
        echo "install.sh: --scaffold needs a target directory" >&2
        exit 2
      fi
      SCAFFOLD_DIR="$2"
      shift
      ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$DO_COMMANDS" -eq 0 ] && [ "$DO_STATUSLINE" -eq 0 ] && [ -z "$SCAFFOLD_DIR" ]; then
  echo "install.sh: nothing to install (use --dry-run together with a component)" >&2
  exit 2
fi

# Display only: print paths under $HOME as ~/... (the tilde is meant literally).
# shellcheck disable=SC2088
short() {
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# install_file <from> <to> <mode: replace|keep>
#   replace: back up a different existing file, then overwrite it
#   keep:    leave an existing file alone (unless --force, then replace)
install_file() {
  local from="$1" to="$2" mode="$3"
  if [ ! -f "$from" ]; then
    printf '  missing in kit, skipped: %s\n' "$(short "$from")"
    return 0
  fi
  if [ -f "$to" ] && cmp -s "$from" "$to"; then
    printf '  unchanged: %s\n' "$(short "$to")"
    return 0
  fi
  if [ -e "$to" ] && [ "$mode" = "keep" ] && [ "$FORCE" -eq 0 ]; then
    printf '  kept (already exists): %s\n' "$(short "$to")"
    return 0
  fi
  if [ -e "$to" ]; then
    if [ "$DRY" -eq 1 ]; then
      printf '  would back up: %s -> %s.bak-%s\n' "$(short "$to")" "$(short "$to")" "$STAMP"
    else
      cp -p "$to" "$to.bak-$STAMP"
      printf '  backed up: %s.bak-%s\n' "$(short "$to")" "$STAMP"
    fi
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '  would write: %s\n' "$(short "$to")"
    return 0
  fi
  mkdir -p "$(dirname "$to")"
  cp -p "$from" "$to"
  printf '  wrote: %s\n' "$(short "$to")"
}

missing=""
for tool in jq python3 git; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done

printf '\ngomio-claude-kit\n'
[ "$DRY" -eq 1 ] && printf '(dry run: nothing will be written)\n'

if [ "$DO_COMMANDS" -eq 1 ]; then
  printf '\ncommands -> %s\n' "$(short "$DEST/commands")"
  install_file "$SRC/commands/review-security.md" "$DEST/commands/review-security.md" replace
  install_file "$SRC/commands/audit-saas.md" "$DEST/commands/audit-saas.md" replace
fi

if [ "$DO_STATUSLINE" -eq 1 ]; then
  printf '\nstatus line and usage report -> %s\n' "$(short "$DEST/scripts")"
  install_file "$SRC/extras/statusline.sh" "$DEST/scripts/statusline.sh" replace
  install_file "$SRC/extras/usage.py" "$DEST/scripts/usage.py" replace
  install_file "$SRC/extras/prices.json" "$DEST/scripts/prices.json" replace
  [ "$DRY" -eq 0 ] && chmod +x "$DEST/scripts/statusline.sh" "$DEST/scripts/usage.py"
fi

if [ -n "$SCAFFOLD_DIR" ]; then
  case "$SCAFFOLD_DIR" in
    /*) target="$SCAFFOLD_DIR" ;;
    *) target="$PWD/$SCAFFOLD_DIR" ;;
  esac
  printf '\nscaffold -> %s\n' "$(short "$target")"
  if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ] && [ ! -f "$target/.agent/state.md" ] && [ "$FORCE" -eq 0 ]; then
    echo "  $target is not empty and is not a scaffold. Use an empty directory, or pass" >&2
    echo "  --force to merge (files that differ are backed up, then replaced)." >&2
    exit 1
  fi
  state_created=0
  [ -e "$target/.agent/state.md" ] || state_created=1
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    install_file "$SRC/scaffold/$rel" "$target/$rel" keep
  done <<EOF_FILES
$(cd "$SRC/scaffold" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | sort)
EOF_FILES
  if [ "$DRY" -eq 0 ]; then
    chmod +x "$target"/.claude/hooks/*.sh "$target/scripts/verify.sh" 2>/dev/null || true
    # The Stop hook compares modification times with .agent/state.md, so a fresh
    # state file must be the newest file in the new project.
    [ "$state_created" -eq 1 ] && touch "$target/.agent/state.md"
  fi
fi

printf '\n'
if [ -n "$missing" ]; then
  printf 'Missing tools:%s\n' "$missing"
  printf '  jq: status line and scaffold hooks; python3: usage.py; git: diff mode and the Stop hook.\n\n'
fi

if [ "$DRY" -eq 1 ]; then
  printf 'Dry run complete. Run again without --dry-run to apply.\n\n'
  exit 0
fi

printf 'Done.\n'
if [ "$DO_COMMANDS" -eq 1 ]; then
  printf '  In any repository: /review-security, /review-security full, /audit-saas exec\n'
fi
if [ "$DO_STATUSLINE" -eq 1 ]; then
  printf '  Status line: add this to %s\n' "$(short "$DEST/settings.json")"
  printf '    "statusLine": { "type": "command", "command": "%s" }\n' "$DEST/scripts/statusline.sh"
  printf '  Usage report: python3 %s --days 7\n' "$(short "$DEST/scripts/usage.py")"
fi
if [ -n "$SCAFFOLD_DIR" ]; then
  printf '  Scaffold: put your brief in references/, then run claude there and type /init-project\n'
fi
printf '\n'
