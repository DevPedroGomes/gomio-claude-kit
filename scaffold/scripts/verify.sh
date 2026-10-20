#!/usr/bin/env bash
#
# Canonical verification entry point.
#
# CLAUDE.md forbids declaring a task DONE without a green run of this script.
# So it MUST fail while it is still unconfigured. An unconfigured script that
# exits 0 would let an agent "verify" nothing and report success.
#
# To configure: fill in the commands below and set CONFIGURED=1.
# Leave a command empty ONLY if it genuinely does not apply to this stack;
# empty commands are reported as SKIPPED so the gap stays visible.

set -uo pipefail

CONFIGURED=0

TEST_CMD=""       # e.g. "pytest -q"            | "npm test"
LINT_CMD=""       # e.g. "ruff check ."         | "npx eslint ."
TYPECHECK_CMD=""  # e.g. "mypy ."               | "npx tsc --noEmit"
BUILD_CMD=""      # e.g. "npm run build"        | "" for libraries/workers
E2E_CMD=""        # e.g. "npx playwright test"  | "" until E2E exists

if [ "$CONFIGURED" -ne 1 ]; then
  cat >&2 <<'EOF'
VERIFICATION NOT CONFIGURED.

scripts/verify.sh still holds placeholder commands, so nothing was verified.
Do not report tests, lint, types or build as passing.

Fix before the first implementation task:
  1. fill TEST_CMD / LINT_CMD / TYPECHECK_CMD / BUILD_CMD / E2E_CMD
  2. set CONFIGURED=1
EOF
  exit 1
fi

failed=0
skipped=0

run_step() {
  local name="$1" cmd="$2"
  printf '\n== %s ==\n' "$name"
  if [ -z "$cmd" ]; then
    echo "SKIPPED (no command configured)"
    skipped=$((skipped + 1))
    return 0
  fi
  echo "\$ $cmd"
  if eval "$cmd"; then
    echo "-> PASS"
  else
    local code=$?
    echo "-> FAIL (exit $code)"
    failed=$((failed + 1))
  fi
}

run_step "Tests"     "$TEST_CMD"
run_step "Lint"      "$LINT_CMD"
run_step "Typecheck" "$TYPECHECK_CMD"
run_step "Build"     "$BUILD_CMD"
run_step "E2E"       "$E2E_CMD"

printf '\n== Summary ==\n'
echo "failed: $failed | skipped: $skipped"

if [ "$failed" -gt 0 ]; then
  echo "VERIFICATION FAILED"
  exit 1
fi

echo "VERIFICATION PASSED"
exit 0
