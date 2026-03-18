#!/usr/bin/env bash
#
# Regression coverage for the /ralph/build single-entry setup wrapper wiring.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAILURES=0

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1"
  FAILURES=$((FAILURES + 1))
}

assert_file_exists() {
  local path="$1"
  local message="$2"
  if [ -f "$path" ]; then
    pass "$message"
  else
    fail "$message (missing file: $path)"
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  if rg -n --fixed-strings "$needle" "$path" >/dev/null; then
    pass "$message"
  else
    fail "$message (missing '$needle' in $path)"
  fi
}

BUILD_COMMAND="$REPO_ROOT/commands/ralph/build.md"
BUILD_CONTRACT="$REPO_ROOT/contracts/ralph/core/commands/build.md"
BUILD_SKILL="$REPO_ROOT/skills/ralph-build/SKILL.md"
MAPPING_FILE="$REPO_ROOT/contracts/ralph/adapters/mapping.md"
CURSOR_ADAPTER="$REPO_ROOT/contracts/ralph/adapters/cursor/README.md"
CODEX_ADAPTER="$REPO_ROOT/contracts/ralph/adapters/codex/README.md"
BOOTSTRAP_SCRIPT="$REPO_ROOT/scripts/bootstrap-ralph-surfaces.sh"
DRIFT_SCRIPT="$REPO_ROOT/scripts/check-ralph-drift.sh"

assert_file_exists "$BUILD_COMMAND" "build wrapper command exists"
assert_file_exists "$BUILD_CONTRACT" "build core contract exists"
assert_file_exists "$BUILD_SKILL" "build Codex skill exists"

assert_contains "$MAPPING_FILE" "| \`build\` | \`/ralph/build\` | \`ralph-build\` | \`../../core/commands/build.md\` |" \
  "adapter mapping includes build row"
assert_contains "$CURSOR_ADAPTER" "| \`build\` | \`/ralph/build\` |" \
  "cursor adapter includes build mapping"
assert_contains "$CODEX_ADAPTER" "| \`build\` | \`ralph-build\` |" \
  "codex adapter includes build mapping"

assert_contains "$BUILD_COMMAND" "BUILD_PHASE phase=<phase-name> status=start" \
  "build wrapper emits phase start marker"
assert_contains "$BUILD_COMMAND" "BUILD_PHASE phase=<phase-name> status=pass" \
  "build wrapper emits phase pass marker"
assert_contains "$BUILD_COMMAND" "BUILD_PHASE phase=<phase-name> status=fail" \
  "build wrapper emits phase failure marker"
assert_contains "$BUILD_COMMAND" "create-project" "build wrapper references create-project phase"
assert_contains "$BUILD_COMMAND" "populate-project" "build wrapper references populate-project phase"
assert_contains "$BUILD_COMMAND" "generate-prd-from-project" "build wrapper references generate-prd phase"
assert_contains "$BUILD_COMMAND" "audit-project" "build wrapper references audit phase"
assert_contains "$BUILD_COMMAND" "Do not invoke \`/ralph/run\` from this wrapper." \
  "build wrapper explicitly stops before runtime execution"

assert_contains "$BUILD_CONTRACT" "1. \`create-project\`" "build contract documents phase 1"
assert_contains "$BUILD_CONTRACT" "2. \`populate-project\`" "build contract documents phase 2"
assert_contains "$BUILD_CONTRACT" "3. \`generate-prd-from-project\`" "build contract documents phase 3"
assert_contains "$BUILD_CONTRACT" "4. \`audit-project\`" "build contract documents phase 4"
assert_contains "$BUILD_CONTRACT" "does not launch \`ralph-run\`" \
  "build contract prohibits automatic runtime launch"

assert_contains "$BUILD_SKILL" "contracts/ralph/core/commands/build.md" \
  "build skill wires to build command contract"
assert_contains "$BUILD_SKILL" "contracts/ralph/core/shared-validations.md" \
  "build skill wires to shared validations"
assert_contains "$BUILD_SKILL" "contracts/ralph/adapters/mapping.md" \
  "build skill wires to mapping contract"

assert_contains "$BOOTSTRAP_SCRIPT" "ralph-build" \
  "bootstrap script includes build skill link target"
assert_contains "$DRIFT_SCRIPT" "skills/ralph-build/SKILL.md" \
  "drift checks include build skill coverage"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS ralph-build wrapper checks passed"
  exit 0
fi

echo "RESULT FAIL ralph-build wrapper checks failed: $FAILURES"
exit 1
