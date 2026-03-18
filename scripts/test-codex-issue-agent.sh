#!/usr/bin/env bash
#
# Regression test: verify that codex-issue-agent.sh builds its prompt
# without executing backticked or $()-substituted literals.
#
# Stubs the codex CLI so the prompt file is captured before deletion,
# then asserts that backticked markdown literals survive verbatim.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR_TEST="$(mktemp -d /tmp/test-codex-issue-agent.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

CAPTURED_PROMPT="$TMPDIR_TEST/captured-prompt.txt"
FAKE_BIN="$TMPDIR_TEST/bin"
mkdir -p "$FAKE_BIN"

# --- stub: codex ---
# Captures the prompt from stdin, writes a valid result JSON, then exits 0.
cat > "$FAKE_BIN/codex" <<'STUB'
#!/usr/bin/env bash
output_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) shift; output_file="$1" ;;
    *) ;;
  esac
  shift
done

cat > "$CAPTURED_PROMPT_PATH"

if [ -n "$output_file" ]; then
  echo "codex stub captured prompt" > "$output_file"
fi

jq -n \
  --arg issue_id "$STUB_ISSUE_ID" \
  '{
    contract_version: "1.0",
    issue_id: $issue_id,
    iteration: 1,
    outcome: "success",
    exit_code: 0,
    failure_category: null,
    retryable: false,
    retry_after_seconds: null,
    handoff_required: false,
    handoff: null,
    summary: "stub success",
    validation_results: { lint: "skipped", typecheck: "skipped", test: "skipped", build: "skipped" },
    artifacts: { commit_hash: null, pr_url: null, files_changed: [] },
    metrics: { duration_ms: 100, tokens_used: null }
  }' > "$STUB_OUTPUT_JSON"

exit 0
STUB
chmod +x "$FAKE_BIN/codex"

# --- stub: node (validate-cli-issue-result.js always passes) ---
cat > "$FAKE_BIN/node" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$FAKE_BIN/node"

passed=0
failed=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    echo "  PASS: $name"
    (( passed++ )) || true
  else
    echo "  FAIL: $name"
    (( failed++ )) || true
  fi
}

echo "=== codex-issue-agent prompt quoting regression tests ==="

# --- build a minimal valid input JSON ---
WORKDIR="$TMPDIR_TEST/workdir"
mkdir -p "$WORKDIR"

OUTPUT_JSON="$TMPDIR_TEST/result.json"
INPUT_JSON="$TMPDIR_TEST/input.json"

jq -n \
  --arg workdir "$WORKDIR" \
  --arg repo_root "$REPO_ROOT" \
  --arg result_path "$OUTPUT_JSON" \
  '{
    contract_version: "1.0",
    iteration: 1,
    issue: {
      id: "TEST-1",
      title: "Test issue with `backticks` and $(command substitution)",
      description: "Verify that `human-in-the-loop` and `Needs Review` and $(echo SHOULD_NOT_RUN) are not executed.",
      priority: 2
    },
    execution_context: {
      branch: "test-branch",
      repo_root: $repo_root,
      workdir: $workdir,
      autocommit: false,
      sync_linear: false,
      workflow_mode: "independent"
    },
    validation_expectations: [],
    artifacts: {
      progress_path: "/tmp/fake-progress.json",
      result_path: $result_path
    }
  }' > "$INPUT_JSON"

# Run the agent with our stubbed PATH
export CAPTURED_PROMPT_PATH="$CAPTURED_PROMPT"
export STUB_ISSUE_ID="TEST-1"
export STUB_OUTPUT_JSON="$OUTPUT_JSON"

PATH="$FAKE_BIN:$PATH" \
  bash "$SCRIPT_DIR/codex-issue-agent.sh" \
    --input-json "$INPUT_JSON" \
    --output-json "$OUTPUT_JSON" \
  2>/dev/null || true

if [ ! -s "$CAPTURED_PROMPT" ]; then
  echo "FATAL: prompt was not captured — stub may not have run."
  exit 1
fi

# --- Test 1: backticked `human-in-the-loop` appears verbatim ---
run_test "backtick human-in-the-loop preserved" \
  grep -qF '`human-in-the-loop`' "$CAPTURED_PROMPT"

# --- Test 2: backticked `Needs Review` appears verbatim ---
run_test "backtick Needs Review preserved" \
  grep -qF '`Needs Review`' "$CAPTURED_PROMPT"

# --- Test 3: backticked `independent` appears verbatim ---
run_test "backtick independent preserved" \
  grep -qF '`independent`' "$CAPTURED_PROMPT"

# --- Test 4: dynamic variables were substituted ---
run_test "workdir substituted" \
  grep -qF "$WORKDIR" "$CAPTURED_PROMPT"

run_test "repo_root substituted" \
  grep -qF "$REPO_ROOT" "$CAPTURED_PROMPT"

run_test "branch substituted" \
  grep -qF "test-branch" "$CAPTURED_PROMPT"

# --- Test 5: no __PLACEHOLDER__ tokens remain after substitution ---
run_test "no leftover __WORKDIR__ placeholders" \
  bash -c '! grep -qF "__WORKDIR__" "$1"' _ "$CAPTURED_PROMPT"

run_test "no leftover __REPO_ROOT__ placeholders" \
  bash -c '! grep -qF "__REPO_ROOT__" "$1"' _ "$CAPTURED_PROMPT"

run_test "no leftover __BRANCH__ placeholders" \
  bash -c '! grep -qF "__BRANCH__" "$1"' _ "$CAPTURED_PROMPT"

# --- Test 6: $() in issue description did not execute ---
# The issue description contains $(echo SHOULD_NOT_RUN).
# If shell expansion happened, the prompt would contain "SHOULD_NOT_RUN" as a
# bare word (without the $() wrapper). The prompt itself never references
# issue description text directly, but we verify the prompt file doesn't
# contain evidence of unexpected command execution.
run_test "no evidence of \$(echo ...) execution in prompt" \
  bash -c '! grep -qF "SHOULD_NOT_RUN" "$1"' _ "$CAPTURED_PROMPT"

echo ""
echo "Results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
  echo "PROMPT CONTENTS (for debugging):"
  cat "$CAPTURED_PROMPT"
  exit 1
fi

exit 0
