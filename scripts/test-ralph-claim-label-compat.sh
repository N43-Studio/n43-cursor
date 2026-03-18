#!/usr/bin/env bash
#
# Regression coverage for deprecated claim-label compatibility in the canonical runner.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/ralph-run.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-claim-label-compat.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1"
  FAILURES=$((FAILURES + 1))
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$message"
  else
    fail "$message (expected=$expected actual=$actual)"
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"
  if [ -e "$path" ]; then
    pass "$message"
  else
    fail "$message (missing path: $path)"
  fi
}

assert_file_missing_or_empty() {
  local path="$1"
  local message="$2"
  if [ ! -e "$path" ]; then
    pass "$message"
  elif [ ! -s "$path" ]; then
    pass "$message"
  else
    fail "$message (unexpected content at: $path)"
  fi
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  if grep -F "$needle" "$path" >/dev/null 2>&1; then
    pass "$message"
  else
    fail "$message (missing '$needle' in $path)"
  fi
}

write_agent() {
  local path="$1"
  local capture_path="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON=""
OUTPUT_JSON=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --input-json)
      shift
      INPUT_JSON="\${1:-}"
      ;;
    --output-json)
      shift
      OUTPUT_JSON="\${1:-}"
      ;;
    *)
      echo "unknown argument: \$1" >&2
      exit 30
      ;;
  esac
  shift
done

issue_id="\$(jq -r '.issue.id' "\$INPUT_JSON")"
iteration="\$(jq -r '.iteration' "\$INPUT_JSON")"
printf '%s\n' "\$issue_id" >> "$capture_path"

jq -n \
  --arg issue_id "\$issue_id" \
  --argjson iteration "\$iteration" \
  '
  {
    contract_version: "1.0",
    issue_id: \$issue_id,
    iteration: \$iteration,
    outcome: "success",
    exit_code: 0,
    failure_category: null,
    retryable: false,
    retry_after_seconds: null,
    handoff_required: false,
    handoff: null,
    summary: "claim-label compatibility fixture",
    validation_results: {
      lint: "pass",
      typecheck: "pass",
      test: "pass",
      build: "pass"
    },
    artifacts: {
      commit_hash: null,
      pr_url: null,
      files_changed: []
    },
    metrics: {
      duration_ms: 0,
      tokens_used: 0
    }
  }' > "\$OUTPUT_JSON"
EOF
  chmod +x "$path"
}

write_prd() {
  local path="$1"
  local issue_id="$2"
  local labels_json="$3"
  local description="${4:-Fixture issue for deprecated claim-label compatibility tests}"
  jq -n \
    --arg issue_id "$issue_id" \
    --argjson labels "$labels_json" \
    --arg description "$description" \
    '
    {
      featureName: "claim-label-compat-fixture",
      branchName: "feature/ralph-wiggum-flow",
      issues: [
        {
          issueId: $issue_id,
          title: "Claim-label compatibility fixture",
          description: $description,
          status: "Backlog",
          labels: $labels,
          passes: false
        }
      ]
    }' > "$path"
}

run_case() {
  local case_name="$1"
  local issue_id="$2"
  local labels_json="$3"
  local description="${4:-Fixture issue for deprecated claim-label compatibility tests}"
  local case_dir="$TMP_ROOT/$case_name"
  local prd_path="$case_dir/prd.json"
  local progress_path="$case_dir/progress.txt"
  local run_log_path="$case_dir/run-log.jsonl"
  local loop_state_path="$case_dir/loop-state.json"
  local results_dir="$case_dir/results"
  local capture_path="$case_dir/issues.log"
  local agent_path="$case_dir/agent.sh"

  mkdir -p "$case_dir"
  write_prd "$prd_path" "$issue_id" "$labels_json" "$description"
  write_agent "$agent_path" "$capture_path"

  local -a cmd=(
    "$RUNNER"
    --prd "$prd_path"
    --max 1
    --agent-cmd "$agent_path"
    --workdir "$REPO_ROOT"
    --progress "$progress_path"
    --run-log "$run_log_path"
    --results-dir "$results_dir"
    --loop-state "$loop_state_path"
    --process-review-feedback-sweep false
    --process-issue-intents false
    --process-retrospective false
    --process-retrospective-improvements false
    --process-model-routing false
  )

  set +e
  "${cmd[@]}" >/dev/null 2>&1
  local rc=$?
  set -e

  printf '%s\n' "$rc"
}

check_legacy_labels_are_non_blocking() {
  local case_name="legacy-labels-compatible"
  local case_dir="$TMP_ROOT/$case_name"
  local run_log_path="$case_dir/run-log.jsonl"
  local capture_path="$case_dir/issues.log"

  local rc
  rc="$(run_case "$case_name" "N43-compat" '["Ralph","PRD Ready","Ralph Queue","Ralph Claimed","Ralph Completed"]')"

  assert_eq "$rc" "0" "runner succeeds when deprecated claim labels coexist with readiness labels"
  assert_file_exists "$capture_path" "compat fixture invokes the issue agent"
  assert_eq "$(wc -l < "$capture_path" | tr -d ' ')" "1" "compat fixture executes exactly one issue"
  assert_eq "$(head -n 1 "$capture_path")" "N43-compat" "compat fixture selects the expected issue"
  assert_eq "$(jq -s '[.[] | select(.result == "success")] | length' "$run_log_path")" "1" "compat fixture records one successful run"
}

check_structural_readiness_without_labels() {
  local case_name="structural-readiness-no-labels"
  local case_dir="$TMP_ROOT/$case_name"
  local capture_path="$case_dir/issues.log"
  local run_log_path="$case_dir/run-log.jsonl"
  local structural_description

  structural_description="$(cat <<'EOF'
## Goal
Allow scheduling without readiness labels.

## Scope
Update runner readiness checks.

## Acceptance Criteria
- [ ] Structural readiness evaluates correctly.

## Validation
- `lint`: n/a
- `test`: n/a

## Metadata Rationale
- `priority=1`
- `estimate=2`
EOF
)"

  local rc
  rc="$(run_case "$case_name" "N43-structural" '[]' "$structural_description")"

  assert_eq "$rc" "0" "runner succeeds when structural readiness is satisfied without labels"
  assert_file_exists "$capture_path" "structural fixture invokes the issue agent"
  assert_eq "$(wc -l < "$capture_path" | tr -d ' ')" "1" "structural fixture executes exactly one issue"
  assert_eq "$(head -n 1 "$capture_path")" "N43-structural" "structural fixture selects the expected issue"
  assert_eq "$(jq -s '[.[] | select(.result == "success")] | length' "$run_log_path")" "1" "structural fixture records one successful run"
}

check_claim_labels_do_not_replace_readiness() {
  local case_name="claim-labels-not-readiness"
  local case_dir="$TMP_ROOT/$case_name"
  local progress_path="$case_dir/progress.txt"
  local capture_path="$case_dir/issues.log"

  local rc
  rc="$(run_case "$case_name" "N43-not-ready" '["Ralph Queue","Ralph Claimed","Ralph Completed"]')"

  assert_eq "$rc" "6" "runner stops with no runnable issue when only deprecated claim labels are present"
  assert_file_missing_or_empty "$capture_path" "non-ready fixture does not invoke the issue agent"
  assert_file_contains "$progress_path" "excluded_readiness=1" "non-ready fixture is excluded by readiness gating"
}

assert_file_exists "$RUNNER" "canonical runner exists"

check_legacy_labels_are_non_blocking
check_structural_readiness_without_labels
check_claim_labels_do_not_replace_readiness

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS claim-label compatibility checks passed"
  exit 0
fi

echo "RESULT FAIL claim-label compatibility checks failed: $FAILURES"
exit 1
