#!/usr/bin/env bash
#
# Smoke tests for the scaffold hooks and scripts/verify.sh.
#
# Each hook is run the way Claude Code runs it: the JSON event on stdin,
# CLAUDE_PROJECT_DIR in the environment. The input shapes follow the hooks
# reference (https://code.claude.com/docs/en/hooks).
#
# Usage: bash tests/hooks.sh        (exit 0 when every case passes)

set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$KIT/scaffold"
HOOKS="$SCAFFOLD/.claude/hooks"
BASH_BIN="$(command -v bash)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-hooks.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
OUT=""
ERR=""
CODE=0

ok()  { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n      exit=%s\n      stdout=%s\n      stderr=%s\n' "$1" "$CODE" "$OUT" "$ERR"; }

# run_hook <script> <project_dir> <json> [extra env assignments...]
run_hook() {
  local script="$1" dir="$2" json="$3"
  shift 3
  local errf="$WORK/stderr"
  OUT=$(printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$dir" "$@" "$BASH_BIN" "$HOOKS/$script" 2>"$errf")
  CODE=$?
  ERR=$(cat "$errf")
}

expect() { # <name> <wanted exit code> [substring expected in stdout+stderr]
  local name="$1" want="$2" needle="${3:-}"
  if [ "$CODE" -ne "$want" ]; then bad "$name"; return; fi
  if [ -n "$needle" ]; then
    case "$OUT$ERR" in *"$needle"*) ;; *) bad "$name"; return ;; esac
  fi
  ok "$name"
}

new_project() { # fresh copy of the scaffold, like install.sh --scaffold
  local dir="$WORK/$1"
  mkdir -p "$dir"
  cp -R "$SCAFFOLD/." "$dir/"
  touch "$dir/.agent/state.md"
  printf '%s' "$dir"
}

pre_tool() { # <dir> <tool> <field> <path>
  printf '{"session_id":"test","transcript_path":"/tmp/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"},"tool_use_id":"toolu_test"}' "$1" "$2" "$3" "$4"
}

echo "== SessionStart: session-context.sh"

P=$(new_project session)
START='{"session_id":"test","transcript_path":"/tmp/t.jsonl","cwd":"'"$P"'","hook_event_name":"SessionStart","source":"compact"}'

run_hook session-context.sh "$P" "$START"
expect "compact: injects state.md" 0 "Status: NOT STARTED"
expect "compact: empty scaffold phase" 0 "Empty scaffold"

echo "guide" > "$P/references/guide.md"
run_hook session-context.sh "$P" "$START"
expect "references without specs: NOT initialized" 0 "NOT initialized"

echo "# Product" > "$P/specs/product.md"
echo "# Task 001" > "$P/tasks/active/001-configure-verify.md"
run_hook session-context.sh "$P" "$START"
expect "specs present: initialized" 0 "Project is initialized"
expect "lists active task, hides template" 0 "- 001-configure-verify.md"
case "$OUT" in *_template.md*) bad "template must not be listed" ;; *) ok "template not listed" ;; esac

rm "$P/.agent/state.md"
run_hook session-context.sh "$P" "$START"
expect "missing state.md is reported" 0 "state.md is missing"

echo
echo "== PreToolUse: protect-references.sh"

P=$(new_project protect)

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/references/guide.md")"
expect "Write into references/ is blocked" 2 "read-only source material"

run_hook protect-references.sh "$P" "$(pre_tool "$P" Edit file_path "$P/specs/product.md")"
expect "Edit in specs/ is allowed" 0
if [ -z "$ERR" ]; then ok "allowed call prints nothing"; else bad "allowed call prints nothing"; fi

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/references/README.md")"
expect "references/README.md stays editable" 0

run_hook protect-references.sh "$P" "$(pre_tool "$P" NotebookEdit notebook_path "$P/references/analysis.ipynb")"
expect "NotebookEdit into references/ is blocked" 2 "read-only"

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/specs/../references/guide.md")"
expect "dot-dot path into references/ is blocked" 2 "read-only"

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/References/Guide.md")"
expect "different case is blocked" 2 "read-only"

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "references/guide.md")"
expect "relative path is blocked" 2 "read-only"

run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$WORK/elsewhere/references/x.md")"
expect "references/ outside the project is allowed" 0

run_hook protect-references.sh "$P" '{"tool_name":"Write","tool_input":{"file_path":"'"$P"'/references/x.md"'
expect "truncated JSON naming references/ is blocked" 2 "could not parse"

ln -s "$P" "$WORK/protect-link"
run_hook protect-references.sh "$WORK/protect-link" "$(pre_tool "$P" Write file_path "$P/references/guide.md")"
expect "symlinked project root still blocks" 2 "read-only"

# Without jq: a PATH holding only the tools the hook needs, plus python3.
NOJQ="$WORK/bin-nojq"
mkdir -p "$NOJQ"
for t in cat tr; do ln -s "$(command -v "$t")" "$NOJQ/$t"; done
# Link the real interpreter, not a version-manager shim that needs a full PATH.
PY_REAL=$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null) && ln -s "$PY_REAL" "$NOJQ/python3"
if [ -x "$NOJQ/python3" ]; then
  run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/references/guide.md")" PATH="$NOJQ"
  expect "no jq, python3 fallback blocks" 2 "read-only"
  run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/src/app.py")" PATH="$NOJQ"
  expect "no jq, python3 fallback allows src/" 0
fi

# Neither jq nor python3: fail closed on anything that mentions references/.
BARE="$WORK/bin-bare"
mkdir -p "$BARE"
for t in cat tr; do ln -s "$(command -v "$t")" "$BARE/$t"; done
run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/references/guide.md")" PATH="$BARE"
expect "no jq and no python3: blocks references/" 2 "could not parse"
run_hook protect-references.sh "$P" "$(pre_tool "$P" Write file_path "$P/src/app.py")" PATH="$BARE"
expect "no jq and no python3: allows src/" 0

echo
echo "== Stop: require-state-update.sh"

STOP_JSON='{"session_id":"test","transcript_path":"/tmp/t.jsonl","cwd":"/x","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done.","background_tasks":[],"session_crons":[]}'
STOP_ACTIVE='{"session_id":"test","transcript_path":"/tmp/t.jsonl","cwd":"/x","permission_mode":"default","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"Done.","background_tasks":[],"session_crons":[]}'

P=$(new_project stop-git)
git -C "$P" init -q
printf 'dist/\n' >> "$P/.gitignore"
touch -t 202001010000 "$P/.agent/state.md"
find "$P" -path "$P/.git" -prune -o -type f -exec touch -t 202001010000 {} +
touch -t 202001010000 "$P/.agent/state.md"

run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "git: nothing changed, stop allowed" 0

mkdir -p "$P/src" && echo "print(1)" > "$P/src/app.py"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "git: code changed after state.md, stop blocked" 2 "src/app.py"

run_hook require-state-update.sh "$P" "$STOP_ACTIVE"
expect "git: stop_hook_active true, never blocks twice" 0

touch "$P/.agent/state.md"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "git: state.md updated, stop allowed" 0

touch -t 202001010000 "$P/.agent/state.md" "$P/src/app.py"
mkdir -p "$P/dist" && echo "x" > "$P/dist/bundle.js"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "git: ignored build output does not block" 0

echo "x" > "$P/.claude/settings.local.json"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "git: settings.local.json does not block" 0

P=$(new_project stop-plain)
find "$P" -type f -exec touch -t 202001010000 {} +
mkdir -p "$P/node_modules/x" && echo "x" > "$P/node_modules/x/index.js"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "no git: node_modules does not block" 0

echo "x" > "$P/main.go"
run_hook require-state-update.sh "$P" "$STOP_JSON"
expect "no git: changed file blocks" 2 "main.go"

echo
echo "== scripts/verify.sh"

P=$(new_project verify)
OUT=$(bash "$P/scripts/verify.sh" 2>&1); CODE=$?; ERR=""
expect "unconfigured verify.sh exits 1" 1 "NOT CONFIGURED"

sed -i.bak -e 's/^CONFIGURED=0/CONFIGURED=1/' -e 's/^TEST_CMD=""/TEST_CMD="true"/' "$P/scripts/verify.sh"
OUT=$(bash "$P/scripts/verify.sh" 2>&1); CODE=$?
expect "configured and green exits 0" 0 "VERIFICATION PASSED"

sed -i.bak -e 's/^TEST_CMD="true"/TEST_CMD="false"/' "$P/scripts/verify.sh"
OUT=$(bash "$P/scripts/verify.sh" 2>&1); CODE=$?
expect "configured with a failing step exits 1" 1 "VERIFICATION FAILED"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
