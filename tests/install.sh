#!/usr/bin/env bash
# Assertions are strings evaluated later by assert(), so single quotes and
# variables that look unused are intended.
# shellcheck disable=SC2016,SC2034
#
# Tests for install.sh. Runs it against throwaway HOME and CLAUDE_CONFIG_DIR
# directories, never the real ones.
#
# Usage: bash tests/install.sh   (run it with /bin/bash on macOS to cover bash 3.2)

set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH:-$(command -v bash)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; }
assert() { if eval "$2"; then ok "$1"; else bad "$1" "      condition: $2"; fi; }

export HOME="$WORK/home"
mkdir -p "$HOME"
CFG="$WORK/config/claude"           # does not exist yet: the installer must create it
inst() { CLAUDE_CONFIG_DIR="$CFG" "$BASH_BIN" "$KIT/install.sh" "$@"; }

echo "bash: $("$BASH_BIN" -c 'echo $BASH_VERSION')"

out=$(inst 2>&1); code=$?
assert "no arguments prints usage and exits 2" '[ $code -eq 2 ] && case "$out" in *--scaffold*) true ;; *) false ;; esac'

out=$(inst --bogus 2>&1); code=$?
assert "unknown option exits 2" '[ $code -eq 2 ]'

out=$(inst --all --dry-run 2>&1); code=$?
assert "dry run exits 0" '[ $code -eq 0 ]'
assert "dry run writes nothing" '[ ! -e "$CFG" ]'
assert "dry run lists the files it would write" 'case "$out" in *"would write"*review-security.md*) true ;; *) false ;; esac'

out=$(inst --all 2>&1); code=$?
assert "install into a missing config dir exits 0" '[ $code -eq 0 ]'
assert "commands installed" '[ -f "$CFG/commands/review-security.md" ] && [ -f "$CFG/commands/audit-saas.md" ]'
assert "scripts installed" '[ -f "$CFG/scripts/usage.py" ] && [ -f "$CFG/scripts/prices.json" ]'
assert "statusline is executable" '[ -x "$CFG/scripts/statusline.sh" ]'
assert "nothing written to ~/.claude when CLAUDE_CONFIG_DIR is set" '[ ! -e "$HOME/.claude" ]'

out=$(inst --all 2>&1); code=$?
assert "second run exits 0" '[ $code -eq 0 ]'
assert "second run changes nothing" 'case "$out" in *wrote:*|*"backed up"*) false ;; *) true ;; esac'
assert "second run leaves no backups" '[ -z "$(find "$CFG" -name "*.bak-*")" ]'

echo "local edit" >> "$CFG/commands/review-security.md"
out=$(inst --commands 2>&1)
assert "changed file is backed up before overwrite" '[ -n "$(find "$CFG/commands" -name "review-security.md.bak-*")" ]'
assert "changed file is restored" 'cmp -s "$KIT/commands/review-security.md" "$CFG/commands/review-security.md"'

out=$(env -u CLAUDE_CONFIG_DIR "$BASH_BIN" "$KIT/install.sh" --commands 2>&1)
assert "without CLAUDE_CONFIG_DIR it uses ~/.claude" '[ -f "$HOME/.claude/commands/audit-saas.md" ]'

P="$WORK/projects/new-app"
out=$(inst --scaffold "$P" 2>&1); code=$?
assert "scaffold into a new directory exits 0" '[ $code -eq 0 ]'
assert "scaffold copies hidden files" '[ -f "$P/.claude/settings.json" ] && [ -f "$P/.agent/state.md" ] && [ -f "$P/tasks/completed/.gitkeep" ]'
assert "scaffold hooks are executable" '[ -x "$P/.claude/hooks/protect-references.sh" ] && [ -x "$P/scripts/verify.sh" ]'
newer=$(find "$P" -type f -newer "$P/.agent/state.md" | head -1)
assert "state.md is the newest file, so the Stop hook starts quiet" '[ -z "$newer" ]'
code=0
printf '{"hook_event_name":"Stop","stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" "$BASH_BIN" "$P/.claude/hooks/require-state-update.sh" 2>/dev/null || code=$?
assert "Stop hook allows the first stop in a fresh scaffold" '[ $code -eq 0 ]'

echo "my state" > "$P/.agent/state.md"
out=$(inst --scaffold "$P" 2>&1); code=$?
assert "re-running the scaffold keeps edited files" '[ $code -eq 0 ] && [ "$(cat "$P/.agent/state.md")" = "my state" ]'
assert "re-running reports kept files" 'case "$out" in *"kept (already exists)"*state.md*) true ;; *) false ;; esac'

O="$WORK/projects/existing"
mkdir -p "$O" && echo "mine" > "$O/README.md"
out=$(inst --scaffold "$O" 2>&1); code=$?
assert "non-empty, non-scaffold directory is refused" '[ $code -eq 1 ] && [ "$(cat "$O/README.md")" = "mine" ]'
out=$(inst --scaffold "$O" --force 2>&1); code=$?
assert "--force merges and backs up the conflicting file" '[ $code -eq 0 ] && [ -n "$(find "$O" -maxdepth 1 -name "README.md.bak-*")" ]'

out=$(inst --scaffold 2>&1); code=$?
assert "--scaffold without a directory exits 2" '[ $code -eq 2 ]'

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
