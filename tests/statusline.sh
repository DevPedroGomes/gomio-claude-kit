#!/usr/bin/env bash
#
# Tests for extras/statusline.sh with the JSON shape documented for the
# Claude Code status line (https://code.claude.com/docs/en/statusline).
#
# Usage: bash tests/statusline.sh

set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$KIT/extras/statusline.sh"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-statusline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
strip() { sed $'s/\033\\[[0-9;]*m//g'; }
check() { # name haystack needle
  case "$2" in
    *"$3"*) pass=$((pass + 1)); printf 'PASS  %s\n' "$1" ;;
    *) fail=$((fail + 1)); printf 'FAIL  %s\n      wanted: %s\n      got:    %s\n' "$1" "$3" "$2" ;;
  esac
}
check_absent() { # name haystack needle
  case "$2" in
    *"$3"*) fail=$((fail + 1)); printf 'FAIL  %s\n      unexpected: %s\n' "$1" "$3" ;;
    *) pass=$((pass + 1)); printf 'PASS  %s\n' "$1" ;;
  esac
}

now=$(date +%s)
full=$(cat <<JSON
{
  "cwd": "$KIT",
  "model": {"id": "claude-opus-5-5", "display_name": "Opus"},
  "workspace": {"current_dir": "$KIT", "project_dir": "$KIT"},
  "context_window": {"used_percentage": 81.6},
  "effort": {"level": "high"},
  "thinking": {"enabled": true},
  "rate_limits": {
    "five_hour": {"used_percentage": 23.5, "resets_at": $((now + 3 * 3600 + 60))},
    "seven_day": {"used_percentage": 41.2, "resets_at": $((now + 4 * 86400 + 60))},
    "spend_limit": {"used_percentage": 62.8, "resets_at": $((now + 630))}
  }
}
JSON
)

out=$(printf '%s' "$full" | "$BASH_BIN" "$SL" | strip)
check "model and effort" "$out" "Opus.high"
check "context percent, floored" "$out" "ctx 81%"
check "5h limit and reset" "$out" "5h 23% ↻3h"
check "7d limit and reset" "$out" "7d 41% ↻4d"
check "gateway spend limit" "$out" "spend 62% ↻10m"
check "git branch shown" "$out" "$(git -C "$KIT" symbolic-ref --short HEAD)"

colored=$(printf '%s' "$full" | "$BASH_BIN" "$SL")
check "context above 75% is red" "$colored" $'\033[31mctx 81%'

minimal='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Sonnet"},"thinking":{"enabled":false}}'
out=$(printf '%s' "$minimal" | "$BASH_BIN" "$SL" | strip)
check "minimal payload still renders" "$out" "Sonnet.no-thinking"
check_absent "no limits before the first response" "$out" "5h"
check_absent "no context before it is known" "$out" "ctx"

out=$(printf '' | "$BASH_BIN" "$SL")
if [ -z "$out" ]; then pass=$((pass + 1)); echo "PASS  empty input prints nothing"; else fail=$((fail + 1)); echo "FAIL  empty input prints nothing"; fi

mkdir -p "$WORK/bin"
ln -s "$(command -v cat)" "$WORK/bin/cat"
out=$(printf '%s' "$full" | env PATH="$WORK/bin" "$BASH_BIN" "$SL")
check "without jq it says so instead of going blank" "$out" "jq not found"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
