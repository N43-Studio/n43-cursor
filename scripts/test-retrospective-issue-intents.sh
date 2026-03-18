#!/usr/bin/env bash
#
# Regression checks for retrospective-generated issue intents.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RETRO_TO_INTENTS="$REPO_ROOT/scripts/retrospective-to-issue-intents.sh"
WORKER="$REPO_ROOT/scripts/issue-intent-worker.sh"
MOCK_CREATOR="$REPO_ROOT/scripts/mock-linear-issue-creator.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-retro-intents.XXXXXX)"

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

assert_true() {
  local actual="$1"
  local message="$2"
  if [ "$actual" = "true" ]; then
    pass "$message"
  else
    fail "$message (expected=true actual=$actual)"
  fi
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

write_retrospective_fixture() {
  local path="$1"
  jq -n '
    {
      contract_version: "1.0",
      generatedAt: "2026-03-17T00:00:00Z",
      proposedImprovements: [
        {
          severity: "critical",
          target: "executor runtime",
          observation: "Nested executor occasionally hangs during long runs.",
          recommendation: "Add deterministic timeout recovery and telemetry."
        },
        {
          severity: "major",
          target: "metadata pipeline",
          observation: "Generated follow-up issues need manual metadata normalization.",
          recommendation: "Emit complete metadata rationale by default."
        },
        {
          severity: "minor",
          target: "docs",
          observation: "Some command examples could be clearer.",
          recommendation: "Refresh examples in README."
        }
      ]
    }' > "$path"
}

run_flow() {
  local case_dir="$TMP_ROOT/retro-flow"
  local retrospective_path="$case_dir/retrospective.json"
  local queue_path="$case_dir/intents.jsonl"
  local enqueue_results_path="$case_dir/enqueue-results.jsonl"
  local worker_results_path="$case_dir/worker-results.jsonl"
  local summary_path="$case_dir/summary.json"
  local worker_summary_path="$case_dir/worker-summary.json"

  mkdir -p "$case_dir"
  write_retrospective_fixture "$retrospective_path"
  : > "$queue_path"
  : > "$enqueue_results_path"
  : > "$worker_results_path"

  "$RETRO_TO_INTENTS" \
    --retrospective "$retrospective_path" \
    --queue "$queue_path" \
    --results "$enqueue_results_path" > "$summary_path"

  assert_file_exists "$summary_path" "retrospective flow writes summary output"
  assert_file_exists "$queue_path" "retrospective flow writes queue output"
  assert_eq "$(jq -r '.considered' "$summary_path")" "2" "retrospective flow only considers critical/major improvements"
  assert_eq "$(jq -r '.enqueued' "$summary_path")" "2" "retrospective flow enqueues all considered improvements"
  assert_eq "$(jq -r '.failed' "$summary_path")" "0" "retrospective flow has no enqueue failures"
  assert_eq "$(jq -s 'length' "$queue_path")" "2" "queue contains two deterministic intent records"

  assert_true "$(jq -s '
    all(.[];
      (.payload.labels as $labels
        | all(["Ralph", "PRD Ready", "Agent Generated", "Ralph Queue", "Improvement"][];
            ($labels | index(.) != null)
          )
      )
    )
  ' "$queue_path")" "default label set includes readiness and queue compatibility labels"

  assert_eq "$(jq -s '[.[] | select((.payload.labels | index("executor-runtime")) != null)] | length' "$queue_path")" "1" "target slug label is added for critical improvement"
  assert_eq "$(jq -s '[.[] | select((.payload.labels | index("metadata-pipeline")) != null)] | length' "$queue_path")" "1" "target slug label is added for major improvement"

  assert_true "$(jq -s '
    all(.[];
      (.payload.priority | type == "number")
      and (.payload.estimate | type == "number")
    )
  ' "$queue_path")" "queued payloads include deterministic priority and estimate values"

  assert_eq "$(jq -s '[.[] | select(.payload.description | test("(?m)^- Severity: critical$")) | .payload.priority][0]' "$queue_path")" "1" "critical improvements keep top-priority floor"

  assert_true "$(jq -s '
    all(.[];
      (.payload.description | test("(?im)^##\\s*Goal\\b"))
      and (.payload.description | test("(?im)^##\\s*Context\\b"))
      and (.payload.description | test("(?im)^##\\s*Scope\\b"))
      and (.payload.description | test("(?im)^##\\s*Acceptance Criteria\\b"))
      and (.payload.description | test("(?im)^##\\s*Validation\\b"))
      and (.payload.description | test("(?im)^##\\s*Metadata Rationale\\b"))
      and (.payload.description | test("(?im)\\bestimatedTokens\\b\\s*="))
      and (.payload.description | test("(?im)\\bconfidence\\b\\s*="))
      and (.payload.description | test("(?im)\\blowConfidence\\b\\s*="))
    )
  ' "$queue_path")" "generated descriptions include structural readiness sections and metadata rationale fields"

  "$WORKER" \
    --queue "$queue_path" \
    --results "$worker_results_path" \
    --creator-cmd "$MOCK_CREATOR" > "$worker_summary_path"

  assert_eq "$(jq -r '.processed' "$worker_summary_path")" "2" "worker processes all pending intents"
  assert_eq "$(jq -r '.created' "$worker_summary_path")" "2" "worker creates all queued intents"
  assert_eq "$(jq -r '.failed' "$worker_summary_path")" "0" "worker reports no creation failures"
  assert_eq "$(jq -s '[.[] | select(.outcome == "created")] | length' "$worker_results_path")" "2" "worker result ledger records created outcomes"
}

assert_file_exists "$RETRO_TO_INTENTS" "retrospective improvement script exists"
assert_file_exists "$WORKER" "issue intent worker script exists"
assert_file_exists "$MOCK_CREATOR" "mock creator script exists"

run_flow

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS retrospective issue-intent checks passed"
  exit 0
fi

echo "RESULT FAIL retrospective issue-intent checks failed: $FAILURES"
exit 1
