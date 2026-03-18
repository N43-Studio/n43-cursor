#!/usr/bin/env bash
#
# Codex-backed backend implementation of the Ralph single-issue CLI execution contract.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULT_VALIDATOR="$SCRIPT_DIR/validate-cli-issue-result.js"
TOKEN_EXTRACTOR="$SCRIPT_DIR/extract-codex-token-usage.sh"

INPUT_JSON=""
OUTPUT_JSON=""
ISSUE_ID="unknown-issue"
ITERATION=1
START_EPOCH_MS=0
prompt_file=""
last_message_file=""
codex_events_file=""
codex_home_dir=""

DEFAULT_VALIDATION_RESULTS='{"lint":"skipped","typecheck":"skipped","test":"skipped","build":"skipped"}'
DEFAULT_ARTIFACTS='{"commit_hash":null,"pr_url":null,"files_changed":[]}'

usage() {
  cat <<'EOF'
Usage: scripts/codex-issue-agent.sh --input-json <path> --output-json <path>
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

cleanup_temp() {
  if [ -n "$prompt_file" ]; then
    rm -f "$prompt_file"
  fi
  if [ -n "$last_message_file" ]; then
    rm -f "$last_message_file"
  fi
  if [ -n "$codex_events_file" ]; then
    rm -f "$codex_events_file"
  fi
  if [ -n "$codex_home_dir" ]; then
    rm -rf "$codex_home_dir"
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

trap cleanup_temp EXIT

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

if ! command -v codex >/dev/null 2>&1; then
  write_retryable_failure "transient_infrastructure" "codex CLI not found on PATH"
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
  elif (.issue.title | type != "string") then "issue.title must be a string"
  elif (.issue.description | type != "string") then "issue.description must be a string"
  elif (.execution_context | type != "object") then "execution_context must be an object"
  elif (.execution_context.branch | type != "string" or length == 0) then "execution_context.branch must be a non-empty string"
  elif (.execution_context.repo_root | type != "string" or length == 0 or (startswith("/") | not)) then "execution_context.repo_root must be an absolute path"
  elif (.execution_context.workdir | type != "string" or length == 0 or (startswith("/") | not)) then "execution_context.workdir must be an absolute path"
  elif (.execution_context.autocommit | type != "boolean") then "execution_context.autocommit must be a boolean"
  elif (.execution_context.sync_linear | type != "boolean") then "execution_context.sync_linear must be a boolean"
  elif (.execution_context.workflow_mode != null and (.execution_context.workflow_mode | IN("independent", "human-in-the-loop") | not)) then "execution_context.workflow_mode must be independent or human-in-the-loop when provided"
  elif (.validation_expectations | type != "array") then "validation_expectations must be an array"
  elif any(.validation_expectations[]?; type != "string") then "validation_expectations entries must be strings"
  elif (.artifacts | type != "object") then "artifacts must be an object"
  elif (.artifacts.progress_path | type != "string" or length == 0) then "artifacts.progress_path must be a non-empty string"
  elif (.artifacts.result_path | type != "string" or length == 0) then "artifacts.result_path must be a non-empty string"
  else "" end
' "$INPUT_JSON")"

if [ -n "$input_validation_error" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: $input_validation_error" "$duration_ms"
fi

branch="$(jq -r '.execution_context.branch' "$INPUT_JSON")"
repo_root="$(jq -r '.execution_context.repo_root' "$INPUT_JSON")"
workdir="$(jq -r '.execution_context.workdir' "$INPUT_JSON")"
workflow_mode="$(jq -r '.execution_context.workflow_mode // "independent"' "$INPUT_JSON")"
input_result_path="$(jq -r '.artifacts.result_path' "$INPUT_JSON")"

if [ ! -d "$repo_root" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: execution_context.repo_root not found: $repo_root" "$duration_ms"
fi

if [ ! -d "$workdir" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: execution_context.workdir not found: $workdir" "$duration_ms"
fi

if [ "$input_result_path" != "$OUTPUT_JSON" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  exit_with_contract_violation "invalid input contract: artifacts.result_path must match --output-json" "$duration_ms"
fi

prompt_file="$(mktemp /tmp/codex-issue-agent-prompt.XXXXXX)"
last_message_file="$(mktemp /tmp/codex-issue-agent-last-message.XXXXXX)"
codex_events_file="$(mktemp /tmp/codex-issue-agent-events.XXXXXX)"
codex_home_dir="$(mktemp -d /tmp/codex-home.XXXXXX)"
mkdir -p "$codex_home_dir/memories"
if [ -f "$HOME/.codex/auth.json" ] && [ ! -e "$codex_home_dir/auth.json" ]; then
  ln -s "$HOME/.codex/auth.json" "$codex_home_dir/auth.json"
fi
if [ -f "$HOME/.codex/config.toml" ] && [ ! -e "$codex_home_dir/config.toml" ]; then
  ln -s "$HOME/.codex/config.toml" "$codex_home_dir/config.toml"
fi
if [ -d "$HOME/.codex/skills" ] && [ ! -e "$codex_home_dir/skills" ]; then
  ln -s "$HOME/.codex/skills" "$codex_home_dir/skills"
fi
if [ -d "$HOME/.codex/rules" ] && [ ! -e "$codex_home_dir/rules" ]; then
  ln -s "$HOME/.codex/rules" "$codex_home_dir/rules"
fi

cat > "$prompt_file" <<'PROMPT_EOF'
You are the real Ralph single-Issue execution agent.

Work on exactly one Linear Issue using the repo at:
__WORKDIR__

Use this execution context:
- Repo root: __REPO_ROOT__
- Workdir: __WORKDIR__
- Branch: __BRANCH__
- Workflow mode: __WORKFLOW_MODE__

Read the input contract JSON from:
__INPUT_JSON__

Write the final result JSON to:
__OUTPUT_JSON__

The result JSON must satisfy:
__REPO_ROOT__/contracts/ralph/core/cli-issue-execution-contract.md
__REPO_ROOT__/contracts/ralph/core/schema/cli-issue-execution-result.schema.json

Required behavior:
1. Read and honor the input JSON contract.
2. Execute exactly one Issue and do not work on any unrelated Issue.
3. Use the repo/workdir/branch context from the input.
4. Run validation expectations from the input in order when relevant.
5. Write the output JSON before exiting.
6. Set outcome, exit_code, failure_category, retryable, handoff_required, handoff, validation_results, artifacts, and metrics accurately.
7. If requirements are ambiguous or blocked on human input, use outcome="human_required", exit_code=20, and populate handoff.
8. If implementation or validations fail, use the deterministic failure taxonomy and exit-code mapping from the contract.
9. Keep terminal output brief; the output JSON file is the source of truth.

Mode-specific behavior:
- If workflow mode is `human-in-the-loop`, resolve review checks and unknowns inside the active execution cycle when possible. Do not rely on interim `Needs Review` transitions or deferred async Linear review for intermediate clarification.
- If workflow mode is `independent`, preserve the existing asynchronous Ralph behavior and leave structured review/handoff artifacts for later Linear follow-up when needed.

Do not ask for interactive confirmation. Make the best deterministic decision you can from the issue and repo context.
PROMPT_EOF

sed -i '' \
  -e "s|__WORKDIR__|$workdir|g" \
  -e "s|__REPO_ROOT__|$repo_root|g" \
  -e "s|__BRANCH__|$branch|g" \
  -e "s|__WORKFLOW_MODE__|$workflow_mode|g" \
  -e "s|__INPUT_JSON__|$INPUT_JSON|g" \
  -e "s|__OUTPUT_JSON__|$OUTPUT_JSON|g" \
  "$prompt_file"

set +e
CODEX_HOME="$codex_home_dir" \
OTEL_SDK_DISABLED="true" \
codex exec \
  --ephemeral \
  --skip-git-repo-check \
  --cd "$workdir" \
  --sandbox workspace-write \
  --json \
  -o "$last_message_file" \
  - < "$prompt_file" > "$codex_events_file"
codex_exit=$?
set -e

if [ ! -f "$OUTPUT_JSON" ]; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  summary="codex exec exited without writing result payload (exit=$codex_exit)"
  if [ -f "$last_message_file" ]; then
    last_message="$(cat "$last_message_file" 2>/dev/null || true)"
    if [ -n "$last_message" ]; then
      summary="$summary; last_message=$last_message"
    fi
  fi
  if [ "$codex_exit" -eq 124 ] || [ "$codex_exit" -eq 137 ]; then
    write_retryable_failure "tool_timeout" "$summary" "$duration_ms" "30"
    exit 11
  fi
  write_retryable_failure "transient_infrastructure" "$summary" "$duration_ms" "30"
  exit 11
fi

if ! jq -e '.' "$OUTPUT_JSON" >/dev/null 2>&1; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_contract_violation "codex exec wrote invalid JSON to result payload" "$duration_ms"
  exit 30
fi

if ! node "$RESULT_VALIDATOR" "$OUTPUT_JSON" >/dev/null 2>&1; then
  duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
  write_contract_violation "codex exec wrote a result payload that does not satisfy the CLI issue execution contract" "$duration_ms"
  exit 30
fi

reported_tokens="$(jq -r '.metrics.tokens_used // "null"' "$OUTPUT_JSON")"
reported_token_usage="$(jq -c '.metrics.token_usage // null' "$OUTPUT_JSON")"
telemetry_tokens="null"
telemetry_token_usage='null'

if [ -x "$TOKEN_EXTRACTOR" ] && [ -s "$codex_events_file" ]; then
  telemetry_tokens="$("$TOKEN_EXTRACTOR" --events "$codex_events_file" 2>/dev/null || printf 'null')"
  telemetry_token_usage="$("$TOKEN_EXTRACTOR" --events "$codex_events_file" --structured 2>/dev/null || printf 'null')"
fi

needs_injection="false"
if [[ "$telemetry_tokens" =~ ^[1-9][0-9]*$ ]] && ! [[ "$reported_tokens" =~ ^[1-9][0-9]*$ ]]; then
  needs_injection="true"
fi
if [ "$reported_token_usage" = "null" ] && [ "$telemetry_token_usage" != "null" ] && jq -e '.total_tokens > 0' >/dev/null 2>&1 <<< "$telemetry_token_usage"; then
  needs_injection="true"
fi

if [ "$needs_injection" = "true" ]; then
  inject_tokens_used="$reported_tokens"
  if [[ "$telemetry_tokens" =~ ^[1-9][0-9]*$ ]] && ! [[ "$reported_tokens" =~ ^[1-9][0-9]*$ ]]; then
    inject_tokens_used="$telemetry_tokens"
  fi

  inject_token_usage="$reported_token_usage"
  if [ "$reported_token_usage" = "null" ] && [ "$telemetry_token_usage" != "null" ]; then
    inject_token_usage="$telemetry_token_usage"
  fi

  tmp_result="$(mktemp)"
  jq --argjson tokens_used "$inject_tokens_used" \
     --argjson token_usage "$inject_token_usage" '
    .metrics.tokens_used = $tokens_used
    | .metrics.token_usage = $token_usage
  ' "$OUTPUT_JSON" > "$tmp_result"
  mv "$tmp_result" "$OUTPUT_JSON"

  if ! node "$RESULT_VALIDATOR" "$OUTPUT_JSON" >/dev/null 2>&1; then
    duration_ms="$(( $(now_epoch_ms) - START_EPOCH_MS ))"
    write_contract_violation "codex exec telemetry injection produced an invalid result payload" "$duration_ms"
    exit 30
  fi
fi

result_exit_code="$(jq -r '.exit_code' "$OUTPUT_JSON")"

exit "$result_exit_code"
