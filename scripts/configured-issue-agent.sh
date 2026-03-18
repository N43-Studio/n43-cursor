#!/usr/bin/env bash
#
# Configured production implementation of the Ralph single-issue CLI execution contract.
# Delegates execution to a separately configured backend command.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_VALIDATOR="$SCRIPT_DIR/validate-cli-issue-result.js"

INPUT_JSON=""
OUTPUT_JSON=""
ISSUE_ID="unknown-issue"
ITERATION=1
START_EPOCH_MS=0

DEFAULT_VALIDATION_RESULTS='{"lint":"skipped","typecheck":"skipped","test":"skipped","build":"skipped"}'
DEFAULT_ARTIFACTS='{"commit_hash":null,"pr_url":null,"files_changed":[]}'

usage() {
  cat <<'EOF'
Usage: scripts/configured-issue-agent.sh --input-json <path> --output-json <path>

Required environment:
  RALPH_ISSUE_EXECUTOR_CMD  Optional override command that implements the CLI issue execution contract.

Default backend:
  scripts/codex-issue-agent.sh

Example:
  RALPH_ISSUE_EXECUTOR_CMD="scripts/codex-issue-agent.sh" \
    scripts/configured-issue-agent.sh --input-json in.json --output-json out.json
EOF
}

now_epoch_ms() {
  printf '%s\n' "$(( $(date +%s) * 1000 ))"
}

ensure_output_parent() {
  if [ -n "$OUTPUT_JSON" ]; then
    mkdir -p "$(dirname "$OUTPUT_JSON")"
  fi
}

write_result() {
  local outcome="$1"
  local exit_code="$2"
  local failure_category_json="$3"
  local retryable_json="$4"
  local retry_after_seconds_json="$5"
  local handoff_required_json="$6"
  local handoff_json="$7"
  local summary="$8"
  local duration_ms="${9:-0}"
  local tokens_used_json="${10:-null}"
  local validation_results_json="${11:-$DEFAULT_VALIDATION_RESULTS}"
  local artifacts_json="${12:-$DEFAULT_ARTIFACTS}"
  local token_usage_json="${13:-null}"

  ensure_output_parent

  jq -n \
    --arg issue_id "$ISSUE_ID" \
    --argjson iteration "$ITERATION" \
    --arg outcome "$outcome" \
    --argjson exit_code "$exit_code" \
    --argjson failure_category "$failure_category_json" \
    --argjson retryable "$retryable_json" \
    --argjson retry_after_seconds "$retry_after_seconds_json" \
    --argjson handoff_required "$handoff_required_json" \
    --argjson handoff "$handoff_json" \
    --arg summary "$summary" \
    --argjson duration_ms "$duration_ms" \
    --argjson tokens_used "$tokens_used_json" \
    --argjson token_usage "$token_usage_json" \
    --argjson validation_results "$validation_results_json" \
    --argjson artifacts "$artifacts_json" \
    '
    {
      contract_version: "1.0",
      issue_id: $issue_id,
      iteration: $iteration,
      outcome: $outcome,
      exit_code: $exit_code,
      failure_category: $failure_category,
      retryable: $retryable,
      retry_after_seconds: $retry_after_seconds,
      handoff_required: $handoff_required,
      handoff: $handoff,
      summary: $summary,
      validation_results: $validation_results,
      artifacts: $artifacts,
      metrics: {
        duration_ms: $duration_ms,
        tokens_used: $tokens_used,
        token_usage: $token_usage
      }
    }' > "$OUTPUT_JSON"
}

write_contract_violation() {
  local summary="$1"
  local duration_ms="${2:-0}"
  write_result "failure" 30 '"tool_contract_violation"' "false" "null" "false" "null" "$summary" "$duration_ms" "null"
}

write_retryable_failure() {
  local failure_category="$1"
  local summary="$2"
  local duration_ms="${3:-0}"
  local retry_after_seconds="${4:-null}"
  write_result "failure" 11 "\"$failure_category\"" "true" "$retry_after_seconds" "false" "null" "$summary" "$duration_ms" "null"
}

exit_with_contract_violation() {
  local summary="$1"
  local duration_ms="${2:-0}"
  write_contract_violation "$summary" "$duration_ms"
  exit 30
}

while [ $# -gt 0 ]; do
  case "$1" in
    --input-json)
      shift
      INPUT_JSON="${1:-}"
      ;;
    --output-json)
      shift
      OUTPUT_JSON="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 30
      ;;
  esac
  shift
done

if [ -z "$INPUT_JSON" ] || [ -z "$OUTPUT_JSON" ]; then
  usage >&2
  if [ -n "$OUTPUT_JSON" ]; then
    write_contract_violation "invalid invocation: --input-json and --output-json are required"
  fi
  exit 30
fi

ensure_output_parent

if [ ! -f "$INPUT_JSON" ]; then
  exit_with_contract_violation "input json not found: $INPUT_JSON"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 30
fi

if ! command -v node >/dev/null 2>&1; then
  write_retryable_failure "transient_infrastructure" "node runtime not found on PATH"
  exit 11
fi

START_EPOCH_MS="$(now_epoch_ms)"

if ! jq -e '.' "$INPUT_JSON" >/dev/null 2>&1; then
  exit_with_contract_violation "input contract is not valid JSON"
fi

ISSUE_ID="$(jq -r '.issue.id // "unknown-issue"' "$INPUT_JSON")"
ITERATION="$(jq -r '.iteration // 1' "$INPUT_JSON")"

input_validation_error="$(jq -r '
  if .contract_version != "1.0" then "contract_version must equal 1.0"
  elif (.iteration | type != "number" or floor != . or . < 1) then "iteration must be an integer >= 1"
  elif (.issue | type != "object") then "issue must be an object"
  elif (.issue.id | type != "string" or length == 0) then "issue.id must be a non-empty string"
  elif (.execution_context | type != "object") then "execution_context must be an object"
  elif (.execution_context.workdir | type != "string" or length == 0 or (startswith("/") | not)) then "execution_context.workdir must be an absolute path"
  elif (.execution_context.workflow_mode != null and (.execution_context.workflow_mode | IN("independent", "human-in-the-loop") | not)) then "execution_context.workflow_mode must be independent or human-in-the-loop when provided"
  elif (.artifacts | type != "object") then "artifacts must be an object"
  elif (.artifacts.result_path | type != "string" or length == 0) then "artifacts.result_path must be a non-empty string"
  else "" end
' "$INPUT_JSON")"

if [ -n "$input_validation_error" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: $input_validation_error" "$duration_ms"
fi

input_result_path="$(jq -r '.artifacts.result_path' "$INPUT_JSON")"
if [ "$input_result_path" != "$OUTPUT_JSON" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: artifacts.result_path must match --output-json" "$duration_ms"
fi

backend_cmd="${RALPH_ISSUE_EXECUTOR_CMD:-}"
if [ -z "$backend_cmd" ]; then
  backend_cmd="$SCRIPT_DIR/codex-issue-agent.sh"
fi

if [ -z "$backend_cmd" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_retryable_failure \
    "transient_infrastructure" \
    "no production issue executor configured; set RALPH_ISSUE_EXECUTOR_CMD to a command that implements the CLI issue execution contract" \
    "$duration_ms" \
    "30"
  exit 11
fi

read -r -a BACKEND_CMD_ARR <<< "$backend_cmd"
if [ "${#BACKEND_CMD_ARR[@]}" -eq 0 ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "RALPH_ISSUE_EXECUTOR_CMD resolved to an empty command" "$duration_ms"
fi

if ! command -v "${BACKEND_CMD_ARR[0]}" >/dev/null 2>&1; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_retryable_failure \
    "transient_infrastructure" \
    "configured issue executor not found: ${BACKEND_CMD_ARR[0]}" \
    "$duration_ms" \
    "30"
  exit 11
fi

configured_realpath="$(command -v "${BACKEND_CMD_ARR[0]}")"
self_realpath="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
if [ "$configured_realpath" = "$self_realpath" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "RALPH_ISSUE_EXECUTOR_CMD must not point to scripts/configured-issue-agent.sh" "$duration_ms"
fi

set +e
"${BACKEND_CMD_ARR[@]}" --input-json "$INPUT_JSON" --output-json "$OUTPUT_JSON"
backend_exit=$?
set -e

if [ ! -f "$OUTPUT_JSON" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  if [ "$backend_exit" -eq 124 ] || [ "$backend_exit" -eq 137 ]; then
    write_retryable_failure "tool_timeout" "configured issue executor exited without writing result payload (exit=$backend_exit)" "$duration_ms" "30"
    exit 11
  fi
  write_retryable_failure "transient_infrastructure" "configured issue executor exited without writing result payload (exit=$backend_exit)" "$duration_ms" "30"
  exit 11
fi

if ! jq -e '.' "$OUTPUT_JSON" >/dev/null 2>&1; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_contract_violation "configured issue executor wrote invalid JSON to result payload" "$duration_ms"
  exit 30
fi

if ! node "$RESULT_VALIDATOR" "$OUTPUT_JSON" >/dev/null 2>&1; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_contract_violation "configured issue executor wrote a result payload that does not satisfy the CLI issue execution contract" "$duration_ms"
  exit 30
fi

result_exit_code="$(jq -r '.exit_code' "$OUTPUT_JSON")"
exit "$result_exit_code"
