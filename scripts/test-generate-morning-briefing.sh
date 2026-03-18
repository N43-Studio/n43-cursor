#!/usr/bin/env bash
#
# Regression checks for deterministic morning briefing generation.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/generate-morning-briefing.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-morning-briefing.XXXXXX)"

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

assert_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  if grep -qF "$needle" "$path"; then
    pass "$message"
  else
    fail "$message (missing '$needle' in $path)"
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

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

write_run_log_fixture() {
  local path="$1"
  cat > "$path" <<'EOF_RUNLOG'
{"timestamp":"2026-03-17T05:00:00Z","issueId":"N43-600","issueTitle":"Successful issue","result":"success","tokensUsed":120,"durationMs":1000,"filesChanged":["scripts/alpha.sh","commands/code-review/foo.md"],"retryable":false,"validationResults":{"lint":"pass","test":"pass"}}
{"timestamp":"2026-03-17T05:45:00Z","issueId":"N43-601","issueTitle":"Failed issue","result":"failure","tokensUsed":80,"durationMs":2000,"filesChanged":["scripts/alpha.sh","README.md"],"retryable":true,"failureCategory":"vague-spec","validationResults":{"lint":"pass","test":"fail"}}
{"timestamp":"2026-03-17T06:10:00Z","issueId":"N43-602","issueTitle":"Human required issue","result":"human_required","tokensUsed":0,"durationMs":500,"filesChanged":[],"handoffRequired":true}
{"timestamp":"2026-03-16T05:00:00Z","issueId":"N43-599","issueTitle":"Outside window","result":"success","tokensUsed":999,"durationMs":9999,"filesChanged":["ignored/file.txt"],"retryable":false}
{"timestamp":"2026-03-17T06:30:00Z","issueId":"N43-601","issueTitle":"Failed issue retry","result":"failure","tokensUsed":50,"durationMs":1500,"filesChanged":["scripts/alpha.sh"],"retryable":false,"failureCategory":"vague-spec"}
EOF_RUNLOG
}

write_progress_fixture() {
  local path="$1"
  cat > "$path" <<'EOF_PROGRESS'
RUN_START timestamp=2026-03-17T04:00:00Z run_id=run-fixture-001
RUN_COMPLETE timestamp=2026-03-17T07:00:00Z run_id=run-fixture-001
EOF_PROGRESS
}

write_retrospective_fixture() {
  local path="$1"
  jq -n '
    {
      contract_version: "1.0",
      generatedAt: "2026-03-17T07:05:00Z",
      runSummary: {
        issuesAttempted: 3,
        passed: 1,
        failed: 2,
        skipped: 0,
        feedbackRequeues: 0
      },
      estimationAccuracy: [
        { issueId: "N43-600" },
        { issueId: "N43-601" },
        { issueId: "N43-602" }
      ],
      proposedImprovements: [
        { severity: "critical", target: "runtime", observation: "Critical runtime issue detected", recommendation: "fix now" },
        { severity: "major", target: "review", observation: "Major review gap found", recommendation: "tighten queue" },
        { severity: "minor", target: "docs", observation: "minor doc gap", recommendation: "refresh docs" }
      ]
    }
  ' > "$path"
}

write_prd_fixture() {
  local path="$1"
  jq -n '
    {
      issues: [
        { issueId: "N43-600", title: "Successful issue", priority: 2, estimate: 3, dependencies: [] },
        { issueId: "N43-601", title: "Failed issue", priority: 1, estimate: 5, dependencies: [] },
        { issueId: "N43-602", title: "Human required issue", priority: 2, estimate: 2, dependencies: [] },
        { issueId: "N43-603", title: "Not yet attempted", priority: 3, estimate: 3, dependencies: ["N43-601"] },
        { issueId: "N43-604", title: "Also remaining", priority: 4, estimate: 1, dependencies: [] }
      ]
    }
  ' > "$path"
}

# ---------------------------------------------------------------------------
# Test: Full run with all inputs
# ---------------------------------------------------------------------------

run_full_case() {
  local case_dir="$TMP_ROOT/full"
  local run_log="$case_dir/run-log.jsonl"
  local retrospective="$case_dir/retrospective.json"
  local progress="$case_dir/progress.txt"
  local prd="$case_dir/prd.json"
  local output_md="$case_dir/morning-briefing.md"
  local output_json="$case_dir/morning-briefing.json"
  local summary="$case_dir/summary.json"

  mkdir -p "$case_dir"
  write_run_log_fixture "$run_log"
  write_progress_fixture "$progress"
  write_retrospective_fixture "$retrospective"
  write_prd_fixture "$prd"

  "$GENERATOR" \
    --run-log "$run_log" \
    --retrospective "$retrospective" \
    --progress "$progress" \
    --prd "$prd" \
    --output "$output_md" \
    --json "$output_json" \
    --run-id run-fixture-001 > "$summary"

  assert_file_exists "$summary" "generator emits compact summary"
  assert_file_exists "$output_md" "generator writes markdown output"
  assert_file_exists "$output_json" "generator writes JSON sidecar"

  # Summary checks
  assert_eq "$(jq -r '.generated' "$summary")" "true" "summary reports generated=true"
  assert_eq "$(jq -r '.iterations_executed' "$summary")" "4" "summary reports windowed iterations"
  assert_eq "$(jq -r '.success_count' "$summary")" "1" "summary success count"
  assert_eq "$(jq -r '.failure_count' "$summary")" "2" "summary failure count"
  assert_eq "$(jq -r '.human_required_count' "$summary")" "1" "summary human-required count"

  # Sidecar section 1: overnight summary
  assert_eq "$(jq -r '.overnight_summary.iterations_executed' "$output_json")" "4" "sidecar windowed iterations"
  assert_eq "$(jq -r '.overnight_summary.success_count' "$output_json")" "1" "sidecar success count"
  assert_eq "$(jq -r '.overnight_summary.total_tokens_used' "$output_json")" "250" "sidecar token sum"

  # Sidecar section 2: issue outcomes
  assert_eq "$(jq -r '.issue_outcomes.completed | length' "$output_json")" "1" "completed issues count"
  assert_eq "$(jq -r '.issue_outcomes.needs_review | length' "$output_json")" "1" "needs-review issues count"
  assert_eq "$(jq -r '.issue_outcomes.blocked_failed | length' "$output_json")" "1" "blocked/failed issues count"
  assert_eq "$(jq -r '.issue_outcomes.all | map(select(.issue_id == "N43-601")) | .[0].attempts' "$output_json")" "2" "N43-601 has 2 attempts"

  # Sidecar section 3: decision queue
  assert_eq "$(jq -r '.decision_queue | length' "$output_json")" "2" "decision queue has 2 entries"
  assert_eq "$(jq -r '.decision_queue[0].outcome' "$output_json")" "human_required" "human_required sorted first"

  # Sidecar section 4: project state from PRD
  assert_eq "$(jq -r '.project_state.total_prd_issues' "$output_json")" "5" "project state total issues"
  assert_eq "$(jq -r '.project_state.completed_count' "$output_json")" "1" "project state completed"
  assert_eq "$(jq -r '.project_state.remaining_count' "$output_json")" "4" "project state remaining"
  assert_eq "$(jq -r '.project_state.dependency_blockers | length' "$output_json")" "1" "one dependency blocker"
  assert_eq "$(jq -r '.project_state.dependency_blockers[0].issue_id' "$output_json")" "N43-603" "N43-603 has dep blocker"

  # Sidecar section 5: risk flags
  risk_count="$(jq -r '.risk_flags | length' "$output_json")"
  if [ "$risk_count" -ge 3 ]; then
    pass "risk flags present (count=$risk_count)"
  else
    fail "expected at least 3 risk flags, got $risk_count"
  fi
  assert_eq "$(jq -r '[.risk_flags[] | select(.flag == "multiple_retries")] | length' "$output_json")" "1" "multiple retries flag for N43-601"
  assert_eq "$(jq -r '[.risk_flags[] | select(.flag == "failed_validation")] | length' "$output_json")" "1" "failed validation flag"

  # Sidecar section 6: recommended actions
  action_count="$(jq -r '.recommended_actions | length' "$output_json")"
  if [ "$action_count" -ge 2 ]; then
    pass "recommended actions present (count=$action_count)"
  else
    fail "expected at least 2 recommended actions, got $action_count"
  fi

  # Markdown section headers
  assert_contains "$output_md" "## 1. Overnight Summary" "markdown has overnight summary"
  assert_contains "$output_md" "## 2. Issue Outcomes" "markdown has issue outcomes"
  assert_contains "$output_md" "## 3. Decision Queue" "markdown has decision queue"
  assert_contains "$output_md" "## 4. Project State" "markdown has project state"
  assert_contains "$output_md" "## 5. Risk Flags" "markdown has risk flags"
  assert_contains "$output_md" "## 6. Recommended Actions" "markdown has recommended actions"
  assert_contains "$output_md" '`N43-602`' "markdown contains human-required issue in decision queue"
  assert_contains "$output_md" "Dependency Blockers" "markdown shows dependency blockers"
}

# ---------------------------------------------------------------------------
# Test: Minimal run (only required args)
# ---------------------------------------------------------------------------

run_minimal_case() {
  local case_dir="$TMP_ROOT/minimal"
  local run_log="$case_dir/run-log.jsonl"
  local output_md="$case_dir/morning-briefing.md"
  local summary="$case_dir/summary.json"

  mkdir -p "$case_dir"
  write_run_log_fixture "$run_log"

  "$GENERATOR" \
    --run-log "$run_log" \
    --output "$output_md" > "$summary"

  assert_file_exists "$output_md" "minimal: markdown written with only required args"
  assert_eq "$(jq -r '.generated' "$summary")" "true" "minimal: summary is valid"
  assert_eq "$(jq -r '.json_path' "$summary")" "null" "minimal: no json sidecar"

  assert_contains "$output_md" "## 4. Project State" "minimal: project state section present"
  assert_contains "$output_md" "No PRD provided" "minimal: project state shows PRD unavailable"
}

# ---------------------------------------------------------------------------
# Test: Window filtering excludes out-of-range entries
# ---------------------------------------------------------------------------

run_window_filter_case() {
  local case_dir="$TMP_ROOT/window"
  local run_log="$case_dir/run-log.jsonl"
  local progress="$case_dir/progress.txt"
  local output_md="$case_dir/morning-briefing.md"
  local output_json="$case_dir/morning-briefing.json"

  mkdir -p "$case_dir"
  write_run_log_fixture "$run_log"
  write_progress_fixture "$progress"

  "$GENERATOR" \
    --run-log "$run_log" \
    --progress "$progress" \
    --output "$output_md" \
    --json "$output_json" >/dev/null

  assert_eq "$(jq -r '.overnight_summary.iterations_executed' "$output_json")" "4" "window: only in-window entries counted"

  # Verify out-of-window issue N43-599 is excluded from outcomes
  assert_eq "$(jq -r '[.issue_outcomes.all[] | select(.issue_id == "N43-599")] | length' "$output_json")" "0" "window: N43-599 excluded"
}

# ---------------------------------------------------------------------------
# Run all cases
# ---------------------------------------------------------------------------

assert_file_exists "$GENERATOR" "morning briefing generator script exists"

run_full_case
run_minimal_case
run_window_filter_case

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS morning briefing generator checks passed"
  exit 0
fi

echo "RESULT FAIL morning briefing generator checks failed: $FAILURES"
exit 1
