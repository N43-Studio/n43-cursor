#!/usr/bin/env bash
#
# Regression coverage for Ralph token-telemetry propagation across run-log,
# retrospective generation, and calibration updates.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/ralph-run.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/ralph-token-telemetry.XXXXXX)"

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

write_prd() {
  local path="$1"
  cat > "$path" <<'EOF'
{
  "featureName": "token-telemetry-fixture",
  "branchName": "feature/ralph-wiggum-flow",
  "issues": [
    {
      "issueId": "N43-telemetry",
      "title": "Token telemetry fixture",
      "description": "Fixture issue for token telemetry propagation tests.",
      "status": "Backlog",
      "labels": ["Ralph", "PRD Ready"],
      "priority": 2,
      "estimatedPoints": 2,
      "passes": false
    }
  ]
}
EOF
}

write_agent() {
  local path="$1"
  local tokens_used_json="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON=""
OUTPUT_JSON=""
TOKENS_USED='$tokens_used_json'

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

jq -n \
  --arg issue_id "\$issue_id" \
  --argjson iteration "\$iteration" \
  --argjson tokens_used "\$TOKENS_USED" \
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
    summary: "token telemetry fixture",
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
      tokens_used: \$tokens_used
    }
  }' > "\$OUTPUT_JSON"
EOF
  chmod +x "$path"
}

run_case() {
  local case_name="$1"
  local tokens_used_json="$2"
  local expected_runlog_tokens="$3"
  local expected_telemetry_available="$4"
  local expected_telemetry_status="$5"
  local expected_tokens_per_estimated_point="$6"
  local expected_usable_samples="$7"
  local expected_tokens_per_point="$8"

  local case_dir="$TMP_ROOT/$case_name"
  local prd_path="$case_dir/prd.json"
  local progress_path="$case_dir/progress.txt"
  local run_log_path="$case_dir/run-log.jsonl"
  local loop_state_path="$case_dir/loop-state.json"
  local results_dir="$case_dir/results"
  local retrospective_path="$case_dir/retrospective.json"
  local calibration_path="$case_dir/calibration.json"
  local agent_path="$case_dir/agent.sh"
  local run_rc=0

  mkdir -p "$case_dir"
  write_prd "$prd_path"
  write_agent "$agent_path" "$tokens_used_json"

  set +e
  "$RUNNER" \
    --prd "$prd_path" \
    --max 1 \
    --agent-cmd "$agent_path" \
    --workdir "$REPO_ROOT" \
    --progress "$progress_path" \
    --run-log "$run_log_path" \
    --results-dir "$results_dir" \
    --loop-state "$loop_state_path" \
    --retrospective "$retrospective_path" \
    --calibration "$calibration_path" \
    --process-review-feedback-sweep false \
    --process-issue-intents false \
    --process-retrospective true \
    --process-calibration-update true \
    --process-retrospective-improvements false \
    --process-model-routing false >/dev/null 2>&1
  run_rc=$?
  set -e

  assert_eq "$run_rc" "0" "$case_name run exits cleanly"
  assert_file_exists "$run_log_path" "$case_name run-log exists"
  assert_file_exists "$retrospective_path" "$case_name retrospective exists"
  assert_file_exists "$calibration_path" "$case_name calibration exists"

  local runlog_tokens
  local telemetry_available
  local retro_actual_tokens
  local retro_reported_attempts
  local retro_missing_attempts
  local retro_status
  local retro_tpp
  local calibration_usable
  local calibration_tpp

  runlog_tokens="$(jq -r '.tokensUsed // "null"' "$run_log_path")"
  telemetry_available="$(jq -r 'if has("tokenTelemetryAvailable") then (.tokenTelemetryAvailable | tostring) else "missing" end' "$run_log_path")"
  retro_actual_tokens="$(jq -r '.estimationAccuracy[0].actualTokens // "null"' "$retrospective_path")"
  retro_reported_attempts="$(jq -r '.estimationAccuracy[0].reportedTokenAttempts // "null"' "$retrospective_path")"
  retro_missing_attempts="$(jq -r '.estimationAccuracy[0].missingTokenAttempts // "null"' "$retrospective_path")"
  retro_status="$(jq -r '.estimationAccuracy[0].tokenTelemetryStatus // "null"' "$retrospective_path")"
  retro_tpp="$(jq -r '.estimationAccuracy[0].tokensPerEstimatedPoint // "null"' "$retrospective_path")"
  calibration_usable="$(jq -r '.global.usableSampleCount // "null"' "$calibration_path")"
  calibration_tpp="$(jq -r '.global.tokensPerPoint // "null"' "$calibration_path")"

  assert_eq "$runlog_tokens" "$expected_runlog_tokens" "$case_name run-log preserves token value"
  assert_eq "$telemetry_available" "$expected_telemetry_available" "$case_name run-log marks telemetry availability"
  assert_eq "$retro_status" "$expected_telemetry_status" "$case_name retrospective telemetry status"
  assert_eq "$retro_tpp" "$expected_tokens_per_estimated_point" "$case_name retrospective tokensPerEstimatedPoint"
  assert_eq "$calibration_usable" "$expected_usable_samples" "$case_name calibration usable sample count"
  assert_eq "$calibration_tpp" "$expected_tokens_per_point" "$case_name calibration tokensPerPoint"

  if [ "$expected_telemetry_available" = "true" ]; then
    assert_eq "$retro_actual_tokens" "$expected_runlog_tokens" "$case_name retrospective uses reported token value"
    assert_eq "$retro_reported_attempts" "1" "$case_name retrospective tracks reported token attempts"
    assert_eq "$retro_missing_attempts" "0" "$case_name retrospective tracks missing token attempts"
  else
    assert_eq "$retro_actual_tokens" "0" "$case_name retrospective falls back to zero aggregate when telemetry missing"
    assert_eq "$retro_reported_attempts" "0" "$case_name retrospective tracks zero reported token attempts"
    assert_eq "$retro_missing_attempts" "1" "$case_name retrospective tracks missing token attempts"
  fi
}

assert_file_exists "$RUNNER" "canonical runner exists"

run_case "reported-telemetry" "4321" "4321" "true" "reported" "2160.5" "1" "2161"
run_case "missing-telemetry" "null" "null" "false" "missing" "null" "0" "3200"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS token telemetry propagation checks passed"
  exit 0
fi

echo "RESULT FAIL token telemetry propagation checks failed: $FAILURES"
exit 1
