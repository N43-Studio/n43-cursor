#!/usr/bin/env bash
#
# Regression coverage for Ralph workflow-mode behavior in the canonical runner.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/ralph-run.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-workflow-modes.XXXXXX)"

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

assert_file_missing() {
  local path="$1"
  local message="$2"
  if [ ! -e "$path" ]; then
    pass "$message"
  else
    fail "$message (unexpected path: $path)"
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

mode="\$(jq -r '.execution_context.workflow_mode // "missing"' "\$INPUT_JSON")"
issue_id="\$(jq -r '.issue.id' "\$INPUT_JSON")"
iteration="\$(jq -r '.iteration' "\$INPUT_JSON")"
printf '%s\n' "\$mode" >> "$capture_path"

jq -n \
  --arg issue_id "\$issue_id" \
  --argjson iteration "\$iteration" \
  --arg mode "\$mode" \
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
    summary: ("mode=" + \$mode),
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

write_requeue_sweep() {
  local path="$1"
  local count_path="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

count=0
if [ -f "$count_path" ]; then
  count="\$(cat "$count_path")"
fi
count=\$((count + 1))
printf '%s\n' "\$count" > "$count_path"

if [ "\$count" -eq 2 ]; then
  requeue='["N43-1"]'
else
  requeue='[]'
fi

jq -n \
  --argjson count "\$count" \
  --argjson requeue "\$requeue" \
  '
  {
    processed_events: 0,
    matched_status_events: 0,
    ignored_events: 0,
    invalid_events: 0,
    requeue_issue_ids: \$requeue,
    previous_index: (\$count - 1),
    next_index: \$count
  }'
EOF
  chmod +x "$path"
}

write_prd() {
  local path="$1"
  cat > "$path" <<'EOF'
{
  "featureName": "workflow-mode-fixture",
  "branchName": "feature/ralph-wiggum-flow",
  "issues": [
    {
      "issueId": "N43-1",
      "title": "Workflow mode fixture",
      "description": "Fixture issue for workflow mode tests",
      "status": "Backlog",
      "labels": ["Ralph", "PRD Ready"],
      "passes": false
    }
  ]
}
EOF
}

run_fixture() {
  local mode="$1"
  local case_dir="$TMP_ROOT/$mode"
  local prd_path="$case_dir/prd.json"
  local progress_path="$case_dir/progress.txt"
  local run_log_path="$case_dir/run-log.jsonl"
  local loop_state_path="$case_dir/loop-state.json"
  local results_dir="$case_dir/results"
  local review_events_path="$case_dir/review-feedback-events.jsonl"
  local review_state_path="$case_dir/review-feedback-state.json"
  local mode_capture_path="$case_dir/modes.log"
  local sweep_count_path="$case_dir/sweep-count.txt"
  local agent_path="$case_dir/agent.sh"
  local sweep_path="$case_dir/sweep.sh"

  mkdir -p "$case_dir"
  write_prd "$prd_path"
  write_agent "$agent_path" "$mode_capture_path"
  write_requeue_sweep "$sweep_path" "$sweep_count_path"

  local -a cmd=(
    "$RUNNER"
    --prd "$prd_path"
    --max 3
    --agent-cmd "$agent_path"
    --workdir "$REPO_ROOT"
    --progress "$progress_path"
    --run-log "$run_log_path"
    --results-dir "$results_dir"
    --loop-state "$loop_state_path"
    --review-feedback-events "$review_events_path"
    --review-feedback-state "$review_state_path"
    --review-feedback-sweep-cmd "$sweep_path"
    --process-issue-intents false
    --process-retrospective false
    --process-retrospective-improvements false
    --process-model-routing false
  )

  if [ "$mode" = "human-in-the-loop" ]; then
    cmd+=(--workflow-mode "$mode")
  fi

  "${cmd[@]}" >/dev/null
}

check_independent_mode() {
  local case_dir="$TMP_ROOT/independent"
  local run_log_path="$case_dir/run-log.jsonl"
  local loop_state_path="$case_dir/loop-state.json"
  local mode_capture_path="$case_dir/modes.log"
  local sweep_count_path="$case_dir/sweep-count.txt"

  run_fixture "independent"

  assert_file_exists "$run_log_path" "independent run writes run-log"
  assert_file_exists "$loop_state_path" "independent run writes loop-state"
  assert_file_exists "$sweep_count_path" "independent mode executes feedback sweep"

  local success_count
  local requeue_count
  local sweep_count
  local first_mode
  local last_mode
  local mode_lines
  local recorded_mode
  local recorded_sweep_enabled

  success_count="$(jq -s '[.[] | select(.result == "success")] | length' "$run_log_path")"
  requeue_count="$(jq -s '[.[] | select(.result == "requeued_for_feedback")] | length' "$run_log_path")"
  sweep_count="$(cat "$sweep_count_path")"
  first_mode="$(head -n 1 "$mode_capture_path")"
  last_mode="$(tail -n 1 "$mode_capture_path")"
  mode_lines="$(wc -l < "$mode_capture_path" | tr -d ' ')"
  recorded_mode="$(jq -r '.options.workflow_mode' "$loop_state_path")"
  recorded_sweep_enabled="$(jq -r '.options.process_review_feedback_sweep' "$loop_state_path")"

  assert_eq "$success_count" "2" "independent mode re-executes issue after async requeue"
  assert_eq "$requeue_count" "1" "independent mode records review-feedback requeue"
  assert_eq "$sweep_count" "3" "independent mode runs sweep on each loop iteration"
  assert_eq "$mode_lines" "2" "independent mode forwards workflow mode to each issue execution"
  assert_eq "$first_mode" "independent" "independent mode is propagated to issue agent"
  assert_eq "$last_mode" "independent" "independent mode remains stable across retries"
  assert_eq "$recorded_mode" "independent" "loop-state records independent workflow mode"
  assert_eq "$recorded_sweep_enabled" "true" "independent mode keeps async feedback sweep enabled"
}

check_human_in_loop_mode() {
  local case_dir="$TMP_ROOT/human-in-the-loop"
  local run_log_path="$case_dir/run-log.jsonl"
  local loop_state_path="$case_dir/loop-state.json"
  local mode_capture_path="$case_dir/modes.log"
  local sweep_count_path="$case_dir/sweep-count.txt"

  run_fixture "human-in-the-loop"

  assert_file_exists "$run_log_path" "human-in-the-loop run writes run-log"
  assert_file_exists "$loop_state_path" "human-in-the-loop run writes loop-state"
  assert_file_missing "$sweep_count_path" "human-in-the-loop disables async feedback sweep"

  local success_count
  local requeue_count
  local mode_lines
  local only_mode
  local recorded_mode
  local recorded_sweep_enabled

  success_count="$(jq -s '[.[] | select(.result == "success")] | length' "$run_log_path")"
  requeue_count="$(jq -s '[.[] | select(.result == "requeued_for_feedback")] | length' "$run_log_path")"
  mode_lines="$(wc -l < "$mode_capture_path" | tr -d ' ')"
  only_mode="$(head -n 1 "$mode_capture_path")"
  recorded_mode="$(jq -r '.options.workflow_mode' "$loop_state_path")"
  recorded_sweep_enabled="$(jq -r '.options.process_review_feedback_sweep' "$loop_state_path")"

  assert_eq "$success_count" "1" "human-in-the-loop keeps issue in a single active-cycle execution"
  assert_eq "$requeue_count" "0" "human-in-the-loop avoids async requeue events"
  assert_eq "$mode_lines" "1" "human-in-the-loop executes the issue once"
  assert_eq "$only_mode" "human-in-the-loop" "human-in-the-loop mode is propagated to issue agent"
  assert_eq "$recorded_mode" "human-in-the-loop" "loop-state records human-in-the-loop mode"
  assert_eq "$recorded_sweep_enabled" "false" "human-in-the-loop forces async feedback sweep off"
}

assert_file_exists "$RUNNER" "canonical runner exists"

check_independent_mode
check_human_in_loop_mode

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS workflow mode regression checks passed"
  exit 0
fi

echo "RESULT FAIL workflow mode regression checks failed: $FAILURES"
exit 1
