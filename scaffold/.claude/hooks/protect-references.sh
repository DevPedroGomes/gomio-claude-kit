#!/usr/bin/env bash
#
# PreToolUse hook (Write|Edit|NotebookEdit).
#
# references/ holds the original source material. It is an input, never an
# artifact: rewriting it destroys the only record of what was asked for.
# Normalized output belongs in specs/.
#
# Exit 2 blocks the tool call and sends stderr to Claude as the reason.
# Exit 0 lets the call through.

set -uo pipefail

payload=$(cat)

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

REASON="references/ is read-only source material. Write the normalized version to specs/ and record any disagreement with the source in .agent/decisions/."

# Read one string field from the hook payload with jq, or python3 as a fallback.
field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for key in sys.argv[1].lstrip(".").split("."):
    data = data.get(key) if isinstance(data, dict) else None
print(data if isinstance(data, str) else "")
' "$1" 2>/dev/null
  else
    return 1
  fi
}

# Fail closed when the payload cannot be parsed: block anything that mentions
# references/, let everything else through.
unparsed() {
  case "$payload" in
    *references/*|*references\\/*)
      block "$REASON (This hook could not parse the request: install jq or python3.)" ;;
  esac
  exit 0
}

path=$(field '.tool_input.file_path') || unparsed
[ -z "$path" ] && { path=$(field '.tool_input.notebook_path') || unparsed; }
[ -z "$path" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -z "$ROOT" ] && ROOT=$(field '.cwd')
[ -z "$ROOT" ] && ROOT="$PWD"

# Lexical normalization: collapse //, . and .. so specs/../references/x is caught.
normalize() {
  local input="$1" out="" seg
  local IFS=/
  set -f
  for seg in $input; do
    case "$seg" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  set +f
  printf '%s' "${out:-/}"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Resolve symlinks in the longest existing prefix of an absolute path. On macOS
# /tmp is /private/tmp and /var is /private/var, so the same file can arrive
# under two spellings.
physical() {
  local p="$1" rest="" base
  while [ "$p" != "/" ] && [ ! -d "$p" ]; do
    rest="/${p##*/}$rest"
    p="${p%/*}"
    [ -z "$p" ] && p="/"
  done
  base=$(cd "$p" 2>/dev/null && pwd -P) || base="$p"
  printf '%s%s' "${base%/}" "$rest"
}

case "$path" in
  /*) ;;
  *) path="$ROOT/$path" ;;
esac
path=$(normalize "$path")
root=$(normalize "$ROOT")

# Lowercase because the default macOS file system is case-insensitive:
# References/ and references/ are the same folder.
targets="$(lower "$path")
$(lower "$(physical "$path")")"
roots="$(lower "$root")
$(lower "$(physical "$root")")"

while IFS= read -r r; do
  [ -z "$r" ] && continue
  prefix="${r%/}/references/"
  while IFS= read -r t; do
    case "$t" in
      "${prefix}readme.md") exit 0 ;;
      "$prefix"*) block "$REASON" ;;
    esac
  done <<EOF_TARGETS
$targets
EOF_TARGETS
done <<EOF_ROOTS
$roots
EOF_ROOTS

exit 0
