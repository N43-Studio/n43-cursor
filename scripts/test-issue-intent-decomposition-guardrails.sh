#!/usr/bin/env bash
#
# Regression checks for decomposition guardrails in delegated issue creation.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENQUEUE="$REPO_ROOT/scripts/issue-intent-enqueue.sh"
WORKER="$REPO_ROOT/scripts/issue-intent-worker.sh"
MOCK_CREATOR="$REPO_ROOT/scripts/mock-linear-issue-creator.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-decomposition-guardrails.XXXXXX)"

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

run_enqueue_guardrail_case() {
  local case_dir="$TMP_ROOT/enqueue-guardrails"
  local queue_path="$case_dir/intents.jsonl"
  local enqueue_results="$case_dir/enqueue-results.jsonl"
  local enqueue_summary="$case_dir/enqueue-summary.json"
  local worker_results="$case_dir/worker-results.jsonl"
  local worker_summary="$case_dir/worker-summary.json"

  mkdir -p "$case_dir"
  : > "$queue_path"
  : > "$enqueue_results"
  : > "$worker_results"

  "$ENQUEUE" \
    --queue "$queue_path" \
    --results "$enqueue_results" \
    --dedup-key "decomposition-safe-1" \
    --title "Replacement child issue" \
    --description "Replacement child for umbrella decomposition" \
    --team "Studio" \
    --supersedes-issue "N43-100" > "$enqueue_summary"

  assert_eq "$(jq -r '.status' "$enqueue_summary")" "enqueued" "enqueue reports enqueued status"
  assert_eq "$(jq -s 'length' "$queue_path")" "1" "queue contains one enqueued intent"
  assert_eq "$(jq -r -s '.[0].payload.supersedes_issue_id' "$queue_path")" "N43-100" "queued payload includes superseded umbrella issue id"

  assert_true "$(jq -s '
    (.[0].payload.decomposition_guardrails.require_children_runnable_before_parent_terminalization == true)
    and (.[0].payload.decomposition_guardrails.forbid_sub_issue_link_to_superseded_parent == true)
    and (.[0].payload.decomposition_guardrails.preferred_parent_terminal_state == "done")
    and ((.[0].payload.decomposition_guardrails.allowed_replacement_link_types // []) | index("related") != null)
    and ((.[0].payload.decomposition_guardrails.allowed_replacement_link_types // []) | index("blockedBy") != null)
    and ((.[0].payload.decomposition_guardrails.allowed_replacement_link_types // []) | index("blocks") != null)
  ' "$queue_path")" "queued payload includes required decomposition guardrails"

  "$WORKER" \
    --queue "$queue_path" \
    --results "$worker_results" \
    --creator-cmd "$MOCK_CREATOR" > "$worker_summary"

  assert_eq "$(jq -r '.processed' "$worker_summary")" "1" "worker processes guarded replacement-child intent"
  assert_eq "$(jq -r '.created' "$worker_summary")" "1" "worker creates guarded replacement-child intent"
  assert_eq "$(jq -r '.failed' "$worker_summary")" "0" "worker reports no failure for guarded replacement-child intent"
}

run_worker_rejects_missing_guardrails_case() {
  local case_dir="$TMP_ROOT/worker-rejects-missing-guardrails"
  local queue_path="$case_dir/intents.jsonl"
  local worker_results="$case_dir/worker-results.jsonl"
  local worker_summary="$case_dir/worker-summary.json"

  mkdir -p "$case_dir"
  : > "$queue_path"
  : > "$worker_results"

  jq -n -c '
    {
      intent_id: "intent-manual-unsafe",
      dedup_key: "decomposition-unsafe-1",
      created_at: "2026-03-17T00:00:00Z",
      status: "pending",
      payload: {
        title: "Unsafe replacement child",
        description: "Missing decomposition guardrails",
        team: "Studio",
        project: null,
        priority: 3,
        estimate: 2,
        labels: ["Ralph"],
        supersedes_issue_id: "N43-200"
      }
    }
  ' > "$queue_path"

  "$WORKER" \
    --queue "$queue_path" \
    --results "$worker_results" \
    --creator-cmd "$MOCK_CREATOR" > "$worker_summary"

  assert_eq "$(jq -r '.processed' "$worker_summary")" "1" "worker processes unsafe replacement-child intent"
  assert_eq "$(jq -r '.created' "$worker_summary")" "0" "worker does not create unsafe replacement-child intent"
  assert_eq "$(jq -r '.failed' "$worker_summary")" "1" "worker fails unsafe replacement-child intent"
  assert_eq "$(jq -s '[.[] | select(.outcome == "failed")] | length' "$worker_results")" "1" "worker result ledger records one failed outcome"
  assert_true "$(jq -s '.[0].error | test("missing required decomposition guardrails")' "$worker_results")" "failure reason identifies missing decomposition guardrails"
}

assert_true "$(test -f "$ENQUEUE" && echo true || echo false)" "issue-intent enqueue script exists"
assert_true "$(test -f "$WORKER" && echo true || echo false)" "issue-intent worker script exists"
assert_true "$(test -f "$MOCK_CREATOR" && echo true || echo false)" "mock creator script exists"

run_enqueue_guardrail_case
run_worker_rejects_missing_guardrails_case

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS decomposition guardrail checks passed"
  exit 0
fi

echo "RESULT FAIL decomposition guardrail checks failed: $FAILURES"
exit 1
