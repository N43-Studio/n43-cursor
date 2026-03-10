#!/usr/bin/env bash
#
# Canonical deterministic Ralph runner over prd.json.
# Executes exactly one issue per iteration via the CLI issue execution contract.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PRD_PATH=""
MAX_ITERATIONS=5
USAGE_LIMIT=""
AUTOCOMMIT="true"
SYNC_LINEAR="false"
RESUME="false"
STALE_AFTER_SECONDS=1800
AGENT_CMD="scripts/mock-issue-agent.sh"
WORKDIR="$REPO_ROOT"
PROGRESS_PATH="progress.txt"
RUN_LOG_PATH="run-log.jsonl"
ASSUMPTIONS_LOG_PATH="assumptions-log.jsonl"
RESULTS_DIR=".ralph/results"
LOOP_STATE_PATH=""
RUN_LOG_ENABLED="true"
ISSUE_INTENT_QUEUE_PATH=""
ISSUE_INTENT_RESULTS_PATH=""
PROCESS_ISSUE_INTENTS="true"
ISSUE_INTENT_WORKER_CMD="scripts/issue-intent-worker.sh"

usage() {
  cat <<'EOF'
Usage: scripts/ralph-run.sh --prd <path> [options]

Options:
  --prd <path>          Path to prd.json (required)
  --max <number>        Maximum iterations (default: 5)
  --usage-limit <num>   Stop when cumulative tokens_used >= limit
  --autocommit <bool>   true|false (default: true)
  --sync-linear <bool>  true|false (default: false)
  --resume <bool>       Resume from loop-state file (default: false)
  --stale-after-seconds <num>  Consider running state stale after N seconds (default: 1800)
  --agent-cmd <command> CLI command for one issue run (default: scripts/mock-issue-agent.sh)
  --workdir <path>      Working directory for issue execution (default: repo root)
  --progress <path>     Progress output path (default: progress.txt)
  --run-log <path|none> JSONL sidecar log path (default: run-log.jsonl; set none to disable)
  --assumptions-log <path>  JSONL assumptions log path (default: assumptions-log.jsonl)
  --results-dir <path>  Directory for input/output payload artifacts (default: .ralph/results)
  --loop-state <path>   Loop state path (default: .cursor/ralph/<project-slug>/loop-state.json)
  --issue-intent-queue <path>    Issue creation intent queue path (default: .cursor/ralph/<project-slug>/issue-creation-intents.jsonl)
  --issue-intent-results <path>  Issue creation result path (default: .cursor/ralph/<project-slug>/issue-creation-results.jsonl)
  --process-issue-intents <bool> Process queued issue intents at run end (default: true)
  --issue-intent-worker-cmd <command> Delegated worker command (default: scripts/issue-intent-worker.sh)
  --help                Show this help
EOF
}

fail() {
  local message="$1"
  local code="${2:-1}"
  if declare -F write_loop_state >/dev/null 2>&1 && [ "${STATE_TRACKING_ACTIVE:-false}" = "true" ] && [ -n "${LOOP_STATE_ABS:-}" ]; then
    write_loop_state "failed" "error" || true
  fi
  echo "ERROR: $message" >&2
  exit "$code"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "missing required command: $cmd"
  fi
}

is_bool() {
  [ "$1" = "true" ] || [ "$1" = "false" ]
}

abs_path() {
  local input="$1"
  if [ "${input#/}" != "$input" ]; then
    printf '%s\n' "$input"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$input"
  fi
}

slugify() {
  local raw="$1"
  if [ -z "$raw" ]; then
    printf 'default\n'
    return
  fi
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
  date +%s
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prd)
      shift
      PRD_PATH="${1:-}"
      ;;
    --max)
      shift
      MAX_ITERATIONS="${1:-}"
      ;;
    --usage-limit)
      shift
      USAGE_LIMIT="${1:-}"
      ;;
    --autocommit)
      shift
      AUTOCOMMIT="${1:-}"
      ;;
    --sync-linear)
      shift
      SYNC_LINEAR="${1:-}"
      ;;
    --resume)
      shift
      RESUME="${1:-}"
      ;;
    --stale-after-seconds)
      shift
      STALE_AFTER_SECONDS="${1:-}"
      ;;
    --agent-cmd)
      shift
      AGENT_CMD="${1:-}"
      ;;
    --workdir)
      shift
      WORKDIR="${1:-}"
      ;;
    --progress)
      shift
      PROGRESS_PATH="${1:-}"
      ;;
    --run-log)
      shift
      RUN_LOG_PATH="${1:-}"
      ;;
    --assumptions-log)
      shift
      ASSUMPTIONS_LOG_PATH="${1:-}"
      ;;
    --results-dir)
      shift
      RESULTS_DIR="${1:-}"
      ;;
    --loop-state)
      shift
      LOOP_STATE_PATH="${1:-}"
      ;;
    --issue-intent-queue)
      shift
      ISSUE_INTENT_QUEUE_PATH="${1:-}"
      ;;
    --issue-intent-results)
      shift
      ISSUE_INTENT_RESULTS_PATH="${1:-}"
      ;;
    --process-issue-intents)
      shift
      PROCESS_ISSUE_INTENTS="${1:-}"
      ;;
    --issue-intent-worker-cmd)
      shift
      ISSUE_INTENT_WORKER_CMD="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[ -n "$PRD_PATH" ] || fail "--prd is required"

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [ "$MAX_ITERATIONS" -lt 1 ]; then
  fail "--max must be an integer >= 1"
fi

if [ -n "$USAGE_LIMIT" ] && { ! [[ "$USAGE_LIMIT" =~ ^[0-9]+$ ]] || [ "$USAGE_LIMIT" -lt 1 ]; }; then
  fail "--usage-limit must be an integer >= 1"
fi

is_bool "$AUTOCOMMIT" || fail "--autocommit must be true|false"
is_bool "$SYNC_LINEAR" || fail "--sync-linear must be true|false"
is_bool "$RESUME" || fail "--resume must be true|false"
is_bool "$PROCESS_ISSUE_INTENTS" || fail "--process-issue-intents must be true|false"

if ! [[ "$STALE_AFTER_SECONDS" =~ ^[0-9]+$ ]] || [ "$STALE_AFTER_SECONDS" -lt 1 ]; then
  fail "--stale-after-seconds must be an integer >= 1"
fi

require_cmd jq

if [ ! -f "$PRD_PATH" ]; then
  fail "PRD not found: $PRD_PATH"
fi

if [ ! -d "$WORKDIR" ]; then
  fail "workdir not found: $WORKDIR"
fi

PRD_ABS="$(abs_path "$PRD_PATH")"

project_name="$(jq -r '.featureName // empty' "$PRD_ABS" 2>/dev/null || true)"
if [ -z "$project_name" ]; then
  project_name="$(basename "$PRD_ABS" .json)"
fi
project_slug="$(slugify "$project_name")"
if [ -z "$project_slug" ]; then
  project_slug="default"
fi

if [ -z "$LOOP_STATE_PATH" ]; then
  LOOP_STATE_PATH=".cursor/ralph/${project_slug}/loop-state.json"
fi
if [ -z "$ISSUE_INTENT_QUEUE_PATH" ]; then
  ISSUE_INTENT_QUEUE_PATH=".cursor/ralph/${project_slug}/issue-creation-intents.jsonl"
fi
if [ -z "$ISSUE_INTENT_RESULTS_PATH" ]; then
  ISSUE_INTENT_RESULTS_PATH=".cursor/ralph/${project_slug}/issue-creation-results.jsonl"
fi

PROGRESS_ABS="$(abs_path "$PROGRESS_PATH")"
ASSUMPTIONS_LOG_ABS="$(abs_path "$ASSUMPTIONS_LOG_PATH")"
RESULTS_ABS="$(abs_path "$RESULTS_DIR")"
LOOP_STATE_ABS="$(abs_path "$LOOP_STATE_PATH")"
ISSUE_INTENT_QUEUE_ABS="$(abs_path "$ISSUE_INTENT_QUEUE_PATH")"
ISSUE_INTENT_RESULTS_ABS="$(abs_path "$ISSUE_INTENT_RESULTS_PATH")"

if [ -z "$RUN_LOG_PATH" ] || [ "$RUN_LOG_PATH" = "none" ]; then
  RUN_LOG_ENABLED="false"
  RUN_LOG_ABS=""
else
  RUN_LOG_ENABLED="true"
  RUN_LOG_ABS="$(abs_path "$RUN_LOG_PATH")"
fi

mkdir -p "$(dirname "$PROGRESS_ABS")" "$(dirname "$ASSUMPTIONS_LOG_ABS")" "$(dirname "$LOOP_STATE_ABS")" "$(dirname "$ISSUE_INTENT_QUEUE_ABS")" "$(dirname "$ISSUE_INTENT_RESULTS_ABS")" "$RESULTS_ABS"
if [ "$RUN_LOG_ENABLED" = "true" ]; then
  mkdir -p "$(dirname "$RUN_LOG_ABS")"
fi
touch "$PROGRESS_ABS"
touch "$ISSUE_INTENT_QUEUE_ABS" "$ISSUE_INTENT_RESULTS_ABS"
if [ "$RUN_LOG_ENABLED" = "true" ]; then
  touch "$RUN_LOG_ABS"
fi

# Split command by shell words; keep agent command simple and deterministic.
read -r -a AGENT_CMD_ARR <<< "$AGENT_CMD"
if [ "${#AGENT_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --agent-cmd value"
fi
if ! command -v "${AGENT_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "agent command not found: ${AGENT_CMD_ARR[0]}"
fi

read -r -a ISSUE_INTENT_WORKER_CMD_ARR <<< "$ISSUE_INTENT_WORKER_CMD"
if [ "${#ISSUE_INTENT_WORKER_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --issue-intent-worker-cmd value"
fi
if [ "$PROCESS_ISSUE_INTENTS" = "true" ] && ! command -v "${ISSUE_INTENT_WORKER_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "issue intent worker command not found: ${ISSUE_INTENT_WORKER_CMD_ARR[0]}"
fi

if ! jq -e '.issues | type == "array"' "$PRD_ABS" >/dev/null; then
  fail "PRD must include an issues array"
fi

blocked_issues_json='[]'
iterations=0
total_tokens_used=0
stop_reason="complete"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_STARTED_AT="$(now_iso)"
RUN_STARTED_EPOCH="$(now_epoch)"
RESUMED_FROM_RUN_ID=""
STALE_RESUME_DETECTED="false"
LAST_ITERATION_JSON="null"
STATE_TRACKING_ACTIVE="false"
ISSUE_INTENT_SUMMARY_JSON='{"processed":0,"created":0,"failed":0,"skipped":0,"created_issue_ids":[],"worker_exit_code":null}'

next_issue() {
  jq -c --argjson blocked "$blocked_issues_json" '
    .issues as $issues
    | [
        $issues[]
        | select((.passes // false) != true)
        | select((.issueId // "") != "")
        | . as $candidate
        | ($candidate.issueId) as $id
        | select(($blocked | index($id)) == null)
        | ($candidate.dependsOn // []) as $deps
        | select(
            ($deps | all(
              . as $dep
              | any($issues[]; (.issueId == $dep) and ((.passes // false) == true))
            ))
          )
        | {
            issueId: $id,
            title: ($candidate.title // ""),
            description: ($candidate.description // ""),
            priority: (
              if ($candidate.priority | type) == "number"
              then $candidate.priority
              else 999999
              end
            ),
            linearIssueId: ($candidate.linearIssueId // null)
          }
      ]
    | sort_by(.priority, .issueId)
    | .[0] // empty
  ' "$PRD_ABS"
}

pending_count() {
  jq '[.issues[] | select((.passes // false) != true)] | length' "$PRD_ABS"
}

completed_count() {
  jq '[.issues[] | select((.passes // false) == true)] | length' "$PRD_ABS"
}

validate_result_contract() {
  local result_path="$1"

  jq -e '
    .contract_version == "1.0"
    and (.issue_id | type == "string" and length > 0)
    and (.iteration | type == "number" and . >= 1)
    and (.outcome | IN("success","failure","human_required"))
    and (.exit_code | IN(0,10,11,20,30))
    and (.retryable | type == "boolean")
    and (.handoff_required | type == "boolean")
    and (.summary | type == "string" and length > 0)
    and (.validation_results | type == "object")
    and (.artifacts | type == "object")
    and (.metrics | type == "object")
  ' "$result_path" >/dev/null
}

add_blocked_issue() {
  local issue_id="$1"
  blocked_issues_json="$(jq -c --arg id "$issue_id" '
    if index($id) == null then . + [$id] else . end
  ' <<< "$blocked_issues_json")"
}

write_loop_state() {
  local status="$1"
  local stop_reason_value="${2:-null}"
  local heartbeat_epoch
  local now_utc
  local pending
  local completed
  local tmp_file

  heartbeat_epoch="$(now_epoch)"
  now_utc="$(now_iso)"
  pending="$(pending_count)"
  completed="$(completed_count)"
  tmp_file="$(mktemp)"

  jq -n \
    --arg contract_version "1.0" \
    --arg run_id "$RUN_ID" \
    --arg status "$status" \
    --arg started_at "$RUN_STARTED_AT" \
    --arg updated_at "$now_utc" \
    --arg prd_path "$PRD_ABS" \
    --arg progress_path "$PROGRESS_ABS" \
    --arg run_log_path "$RUN_LOG_ABS" \
    --arg run_log_enabled "$RUN_LOG_ENABLED" \
    --arg assumptions_log_path "$ASSUMPTIONS_LOG_ABS" \
    --arg loop_state_path "$LOOP_STATE_ABS" \
    --arg issue_intent_queue_path "$ISSUE_INTENT_QUEUE_ABS" \
    --arg issue_intent_results_path "$ISSUE_INTENT_RESULTS_ABS" \
    --arg process_issue_intents "$PROCESS_ISSUE_INTENTS" \
    --arg issue_intent_worker_cmd "$ISSUE_INTENT_WORKER_CMD" \
    --argjson started_epoch "$RUN_STARTED_EPOCH" \
    --argjson heartbeat_epoch "$heartbeat_epoch" \
    --argjson max_iterations "$MAX_ITERATIONS" \
    --argjson usage_limit_num "$(if [ -n "$USAGE_LIMIT" ]; then echo "$USAGE_LIMIT"; else echo null; fi)" \
    --arg autocommit "$AUTOCOMMIT" \
    --arg sync_linear "$SYNC_LINEAR" \
    --arg resume "$RESUME" \
    --argjson stale_after_seconds "$STALE_AFTER_SECONDS" \
    --arg resumed_from_run_id "$RESUMED_FROM_RUN_ID" \
    --argjson stale_resume_detected "$STALE_RESUME_DETECTED" \
    --argjson iterations_executed "$iterations" \
    --argjson total_tokens_used "$total_tokens_used" \
    --argjson pending_remaining "$pending" \
    --argjson completed_count "$completed" \
    --argjson blocked_issues "$blocked_issues_json" \
    --argjson last_iteration "$LAST_ITERATION_JSON" \
    --argjson issue_intent_summary "$ISSUE_INTENT_SUMMARY_JSON" \
    --arg stop_reason "$stop_reason_value" \
    '
    {
      contract_version: $contract_version,
      run_id: $run_id,
      status: $status,
      started_at: $started_at,
      started_epoch: $started_epoch,
      updated_at: $updated_at,
      last_heartbeat_at: $updated_at,
      last_heartbeat_epoch: $heartbeat_epoch,
      prd_path: $prd_path,
      artifacts: {
        progress_path: $progress_path,
        run_log_path: (if $run_log_path == "" then null else $run_log_path end),
        run_log_enabled: ($run_log_enabled == "true"),
        assumptions_log_path: $assumptions_log_path,
        loop_state_path: $loop_state_path,
        issue_intent_queue_path: $issue_intent_queue_path,
        issue_intent_results_path: $issue_intent_results_path
      },
      options: {
        max_iterations: $max_iterations,
        usage_limit: $usage_limit_num,
        autocommit: ($autocommit == "true"),
        sync_linear: ($sync_linear == "true"),
        resume: ($resume == "true"),
        stale_after_seconds: $stale_after_seconds,
        process_issue_intents: ($process_issue_intents == "true"),
        issue_intent_worker_cmd: $issue_intent_worker_cmd
      },
      counters: {
        iterations_executed: $iterations_executed,
        total_tokens_used: $total_tokens_used,
        pending_remaining: $pending_remaining,
        completed_count: $completed_count,
        blocked_issue_count: ($blocked_issues | length)
      },
      stop_reason: (if $stop_reason == "null" then null else $stop_reason end),
      blocked_issues: $blocked_issues,
      last_iteration: $last_iteration,
      issue_intents: $issue_intent_summary,
      resume_context: {
        resumed_from_run_id: (if $resumed_from_run_id == "" then null else $resumed_from_run_id end),
        stale_resume_detected: $stale_resume_detected
      }
    }' > "$tmp_file"

  mv "$tmp_file" "$LOOP_STATE_ABS"
}

load_resume_state() {
  local current_epoch
  local prior_status
  local prior_run_id
  local prior_heartbeat_epoch
  local prior_age
  local prior_prd_path
  local prior_started_at
  local prior_started_epoch

  current_epoch="$(now_epoch)"
  prior_status="$(jq -r '.status // "unknown"' "$LOOP_STATE_ABS")"
  prior_run_id="$(jq -r '.run_id // ""' "$LOOP_STATE_ABS")"
  prior_heartbeat_epoch="$(jq -r '.last_heartbeat_epoch // 0' "$LOOP_STATE_ABS")"
  prior_prd_path="$(jq -r '.prd_path // ""' "$LOOP_STATE_ABS")"
  prior_started_at="$(jq -r '.started_at // ""' "$LOOP_STATE_ABS")"
  prior_started_epoch="$(jq -r '.started_epoch // 0' "$LOOP_STATE_ABS")"

  if ! [[ "$prior_heartbeat_epoch" =~ ^[0-9]+$ ]]; then
    prior_heartbeat_epoch=0
  fi
  if ! [[ "$prior_started_epoch" =~ ^[0-9]+$ ]]; then
    prior_started_epoch=0
  fi

  prior_age=$((current_epoch - prior_heartbeat_epoch))

  if [ -n "$prior_prd_path" ] && [ "$prior_prd_path" != "$PRD_ABS" ]; then
    fail "loop-state PRD mismatch: state=$prior_prd_path current=$PRD_ABS"
  fi

  if [ "$prior_status" = "running" ] && [ "$prior_age" -le "$STALE_AFTER_SECONDS" ]; then
    fail "existing run appears active (last heartbeat ${prior_age}s ago). Retry later or increase --stale-after-seconds."
  fi

  if [ "$prior_status" = "running" ] && [ "$prior_age" -gt "$STALE_AFTER_SECONDS" ]; then
    STALE_RESUME_DETECTED="true"
  fi

  blocked_issues_json="$(jq -c '.blocked_issues // []' "$LOOP_STATE_ABS")"
  iterations="$(jq -r '.counters.iterations_executed // 0' "$LOOP_STATE_ABS")"
  total_tokens_used="$(jq -r '.counters.total_tokens_used // 0' "$LOOP_STATE_ABS")"
  LAST_ITERATION_JSON="$(jq -c '.last_iteration // null' "$LOOP_STATE_ABS")"
  ISSUE_INTENT_SUMMARY_JSON="$(jq -c '.issue_intents // {"processed":0,"created":0,"failed":0,"skipped":0,"created_issue_ids":[],"worker_exit_code":null}' "$LOOP_STATE_ABS")"

  if ! [[ "$iterations" =~ ^[0-9]+$ ]]; then
    iterations=0
  fi
  if ! [[ "$total_tokens_used" =~ ^[0-9]+$ ]]; then
    total_tokens_used=0
  fi

  if [ -n "$prior_run_id" ]; then
    RUN_ID="$prior_run_id"
    RESUMED_FROM_RUN_ID="$prior_run_id"
  fi

  if [ -n "$prior_started_at" ]; then
    RUN_STARTED_AT="$prior_started_at"
  fi
  if [ "$prior_started_epoch" -gt 0 ]; then
    RUN_STARTED_EPOCH="$prior_started_epoch"
  fi
}

run_issue_intent_worker() {
  local worker_exit=0
  local worker_output_file=""
  local worker_output=""
  local fallback_summary=""

  if [ "$PROCESS_ISSUE_INTENTS" != "true" ]; then
    ISSUE_INTENT_SUMMARY_JSON="$(jq -n -c '
      {
        processed: 0,
        created: 0,
        failed: 0,
        skipped: 0,
        created_issue_ids: [],
        worker_exit_code: null,
        mode: "disabled"
      }')"
    return
  fi

  if [ ! -s "$ISSUE_INTENT_QUEUE_ABS" ]; then
    ISSUE_INTENT_SUMMARY_JSON="$(jq -n -c '
      {
        processed: 0,
        created: 0,
        failed: 0,
        skipped: 0,
        created_issue_ids: [],
        worker_exit_code: 0,
        mode: "no_pending_intents"
      }')"
    return
  fi

  worker_output_file="$(mktemp)"
  set +e
  "${ISSUE_INTENT_WORKER_CMD_ARR[@]}" \
    --queue "$ISSUE_INTENT_QUEUE_ABS" \
    --results "$ISSUE_INTENT_RESULTS_ABS" > "$worker_output_file" 2>&1
  worker_exit=$?
  set -e

  worker_output="$(cat "$worker_output_file" 2>/dev/null || true)"

  if [ -n "$worker_output" ] && jq -e '.' >/dev/null 2>&1 <<< "$worker_output"; then
    ISSUE_INTENT_SUMMARY_JSON="$(jq -c --argjson worker_exit_code "$worker_exit" '
      . + {worker_exit_code: $worker_exit_code}
    ' <<< "$worker_output")"
  else
    fallback_summary="$(jq -n -c \
      --arg output "$worker_output" \
      --argjson worker_exit_code "$worker_exit" \
      '
      {
        processed: 0,
        created: 0,
        failed: 0,
        skipped: 0,
        created_issue_ids: [],
        worker_exit_code: $worker_exit_code,
        mode: "invalid_worker_output",
        worker_output: $output
      }')"
    ISSUE_INTENT_SUMMARY_JSON="$fallback_summary"
  fi

  rm -f "$worker_output_file"
}

if [ "$RESUME" = "true" ]; then
  if [ ! -f "$LOOP_STATE_ABS" ]; then
    fail "--resume=true requires existing loop-state file: $LOOP_STATE_ABS"
  fi
  load_resume_state
else
  if [ -f "$LOOP_STATE_ABS" ]; then
    existing_status="$(jq -r '.status // "unknown"' "$LOOP_STATE_ABS")"
    existing_heartbeat_epoch="$(jq -r '.last_heartbeat_epoch // 0' "$LOOP_STATE_ABS")"
    if ! [[ "$existing_heartbeat_epoch" =~ ^[0-9]+$ ]]; then
      existing_heartbeat_epoch=0
    fi
    existing_age=$(( $(now_epoch) - existing_heartbeat_epoch ))
    if [ "$existing_status" = "running" ] && [ "$existing_age" -le "$STALE_AFTER_SECONDS" ]; then
      fail "existing run appears active (${existing_age}s heartbeat age). Use --resume=true after stale threshold."
    fi
    if [ "$existing_status" = "running" ] && [ "$existing_age" -gt "$STALE_AFTER_SECONDS" ]; then
      fail "stale running loop-state detected; rerun with --resume=true to recover safely"
    fi
  fi
fi

write_loop_state "running" "null"
STATE_TRACKING_ACTIVE="true"
echo "RUN_START timestamp=$(now_iso) prd=$PRD_ABS max=$MAX_ITERATIONS resume=$RESUME loop_state=$LOOP_STATE_ABS run_log_enabled=$RUN_LOG_ENABLED" | tee -a "$PROGRESS_ABS"

while [ "$iterations" -lt "$MAX_ITERATIONS" ]; do
  if [ -n "$USAGE_LIMIT" ] && [ "$total_tokens_used" -ge "$USAGE_LIMIT" ]; then
    stop_reason="usage_limit"
    break
  fi

  issue_json="$(next_issue)"
  if [ -z "$issue_json" ]; then
    if [ "$(pending_count)" -gt 0 ]; then
      stop_reason="no_dependency_ready_issue"
    else
      stop_reason="complete"
    fi
    break
  fi

  iterations=$((iterations + 1))
  issue_id="$(jq -r '.issueId' <<< "$issue_json")"
  issue_title="$(jq -r '.title' <<< "$issue_json")"
  issue_description="$(jq -r '.description' <<< "$issue_json")"
  issue_priority_json="$(jq -c '.priority' <<< "$issue_json")"
  linear_issue_id="$(jq -r '.linearIssueId // empty' <<< "$issue_json")"
  safe_issue_id="${issue_id//[^A-Za-z0-9._-]/_}"

  payload_path="$RESULTS_ABS/${safe_issue_id}-iter-${iterations}-input.json"
  result_path="$RESULTS_ABS/${safe_issue_id}-iter-${iterations}-result.json"

  jq -n \
    --arg contract_version "1.0" \
    --argjson iteration "$iterations" \
    --arg issue_id "$issue_id" \
    --arg title "$issue_title" \
    --arg description "$issue_description" \
    --argjson priority "$issue_priority_json" \
    --arg linear_issue_id "$linear_issue_id" \
    --arg branch "$(jq -r '.branchName // "feature/ralph-run"' "$PRD_ABS")" \
    --arg repo_root "$REPO_ROOT" \
    --arg workdir "$WORKDIR" \
    --argjson autocommit "$AUTOCOMMIT" \
    --argjson sync_linear "$SYNC_LINEAR" \
    --arg run_log_path "$RUN_LOG_ABS" \
    --arg progress_path "$PROGRESS_ABS" \
    --arg result_path "$result_path" \
    '
    {
      contract_version: $contract_version,
      iteration: $iteration,
      issue: {
        id: $issue_id,
        title: $title,
        description: $description,
        priority: $priority,
        linear_issue_id: (if $linear_issue_id == "" then null else $linear_issue_id end)
      },
      execution_context: {
        branch: $branch,
        repo_root: $repo_root,
        workdir: $workdir,
        autocommit: $autocommit,
        sync_linear: $sync_linear
      },
      validation_expectations: ["lint", "typecheck", "test", "build"],
      artifacts: {
        run_log_path: $run_log_path,
        progress_path: $progress_path,
        result_path: $result_path
      }
    }' > "$payload_path"

  start_epoch_ms=$(( $(date +%s) * 1000 ))
  set +e
  "${AGENT_CMD_ARR[@]}" --input-json "$payload_path" --output-json "$result_path"
  agent_cmd_exit=$?
  set -e
  end_epoch_ms=$(( $(date +%s) * 1000 ))
  duration_ms=$((end_epoch_ms - start_epoch_ms))

  if [ ! -f "$result_path" ]; then
    jq -n \
      --arg issue_id "$issue_id" \
      --argjson iteration "$iterations" \
      --arg summary "agent command failed without writing a result payload" \
      --argjson duration_ms "$duration_ms" \
      --argjson agent_exit "$agent_cmd_exit" \
      '
      {
        contract_version: "1.0",
        issue_id: $issue_id,
        iteration: $iteration,
        outcome: "failure",
        exit_code: 30,
        failure_category: "tool_contract_violation",
        retryable: false,
        retry_after_seconds: null,
        handoff_required: false,
        handoff: null,
        summary: ($summary + " (agent exit: " + ($agent_exit|tostring) + ")"),
        validation_results: {
          lint: "skipped",
          typecheck: "skipped",
          test: "skipped",
          build: "skipped"
        },
        artifacts: {
          commit_hash: null,
          pr_url: null,
          files_changed: []
        },
        metrics: {
          duration_ms: $duration_ms,
          tokens_used: null
        }
      }
      ' > "$result_path"
  fi

  validate_result_contract "$result_path" || fail "result contract validation failed for $issue_id" 30

  outcome="$(jq -r '.outcome' "$result_path")"
  result_exit_code="$(jq -r '.exit_code' "$result_path")"
  retryable="$(jq -r '.retryable' "$result_path")"
  handoff_required="$(jq -r '.handoff_required' "$result_path")"
  failure_category="$(jq -r '.failure_category // "none"' "$result_path")"
  summary="$(jq -r '.summary' "$result_path")"
  tokens_used="$(jq -r '.metrics.tokens_used // 0' "$result_path")"

  if ! [[ "$tokens_used" =~ ^[0-9]+$ ]]; then
    tokens_used=0
  fi
  total_tokens_used=$((total_tokens_used + tokens_used))
  iteration_timestamp="$(now_iso)"

  if [ "$RUN_LOG_ENABLED" = "true" ]; then
    jq -n -c \
      --arg timestamp "$iteration_timestamp" \
      --arg issue_id "$issue_id" \
      --arg issue_title "$issue_title" \
      --argjson iteration "$iterations" \
      --arg outcome "$outcome" \
      --argjson agent_exit "$agent_cmd_exit" \
      --argjson result_exit "$result_exit_code" \
      --arg failure_category "$failure_category" \
      --arg summary "$summary" \
      --argjson duration_ms "$duration_ms" \
      --argjson tokens_used "$tokens_used" \
      --slurpfile result "$result_path" \
      '
      {
        timestamp: $timestamp,
        issueId: $issue_id,
        issueTitle: $issue_title,
        iteration: $iteration,
        result: $outcome,
        agentCommandExitCode: $agent_exit,
        contractExitCode: $result_exit,
        failureCategory: $failure_category,
        summary: $summary,
        durationMs: $duration_ms,
        tokensUsed: $tokens_used,
        validationResults: $result[0].validation_results,
        filesChanged: $result[0].artifacts.files_changed,
        commitHash: $result[0].artifacts.commit_hash,
        prUrl: $result[0].artifacts.pr_url,
        retryable: $result[0].retryable,
        handoffRequired: $result[0].handoff_required
      }' >> "$RUN_LOG_ABS"
  fi

  LAST_ITERATION_JSON="$(jq -n -c \
    --arg timestamp "$iteration_timestamp" \
    --arg issue_id "$issue_id" \
    --arg outcome "$outcome" \
    --arg failure_category "$failure_category" \
    --arg summary "$summary" \
    --argjson iteration "$iterations" \
    --argjson result_exit "$result_exit_code" \
    --argjson retryable "$retryable" \
    --argjson handoff_required "$handoff_required" \
    --argjson duration_ms "$duration_ms" \
    --argjson tokens_used "$tokens_used" \
    '
    {
      timestamp: $timestamp,
      iteration: $iteration,
      issue_id: $issue_id,
      outcome: $outcome,
      contract_exit_code: $result_exit,
      failure_category: $failure_category,
      summary: $summary,
      retryable: $retryable,
      handoff_required: $handoff_required,
      duration_ms: $duration_ms,
      tokens_used: $tokens_used
    }')"

  echo "RUN_ITERATION timestamp=$iteration_timestamp iteration=$iterations issue=$issue_id outcome=$outcome retryable=$retryable handoff=$handoff_required" | tee -a "$PROGRESS_ABS"

  if [ "$outcome" = "success" ]; then
    tmp_prd="$(mktemp)"
    jq --arg id "$issue_id" '
      .issues = (.issues | map(
        if .issueId == $id then . + {passes: true} else . end
      ))
    ' "$PRD_ABS" > "$tmp_prd"
    mv "$tmp_prd" "$PRD_ABS"
    write_loop_state "running" "null"
    continue
  fi

  if [ "$handoff_required" = "true" ]; then
    add_blocked_issue "$issue_id"
    jq -n -c \
      --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg issue_id "$issue_id" \
      --slurpfile result "$result_path" \
      '
      {
        timestamp: $timestamp,
        issueId: $issue_id,
        assumptionsMade: $result[0].handoff.assumptions_made,
        questionsForHuman: $result[0].handoff.questions_for_human,
        impactIfWrong: $result[0].handoff.impact_if_wrong,
        proposedRevisionPlan: $result[0].handoff.proposed_revision_plan
      }' >> "$ASSUMPTIONS_LOG_ABS"
    write_loop_state "running" "null"
    continue
  fi

  if [ "$retryable" = "false" ]; then
    add_blocked_issue "$issue_id"
  fi

  write_loop_state "running" "null"
done

pending_remaining="$(pending_count)"
completed_count="$(jq '[.issues[] | select((.passes // false) == true)] | length' "$PRD_ABS")"

if [ "$pending_remaining" -gt 0 ] && [ "$iterations" -ge "$MAX_ITERATIONS" ] && [ "$stop_reason" = "complete" ]; then
  stop_reason="max_iterations"
fi

run_issue_intent_worker
issue_intent_processed="$(jq -r '.processed // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_created="$(jq -r '.created // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_failed="$(jq -r '.failed // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_worker_exit="$(jq -r '.worker_exit_code // "null"' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_created_ids="$(jq -r '.created_issue_ids // [] | join(",")' <<< "$ISSUE_INTENT_SUMMARY_JSON")"

echo "RUN_ISSUE_INTENTS timestamp=$(now_iso) processed=$issue_intent_processed created=$issue_intent_created failed=$issue_intent_failed worker_exit=$issue_intent_worker_exit created_issue_ids=$issue_intent_created_ids" | tee -a "$PROGRESS_ABS"
echo "RUN_COMPLETE timestamp=$(now_iso) iterations=$iterations completed=$completed_count pending=$pending_remaining stop_reason=$stop_reason tokens_used=$total_tokens_used issue_intents_processed=$issue_intent_processed issue_intents_created=$issue_intent_created issue_intents_failed=$issue_intent_failed" | tee -a "$PROGRESS_ABS"

if [ "$pending_remaining" -eq 0 ]; then
  write_loop_state "completed" "complete"
  exit 0
fi

write_loop_state "stopped" "$stop_reason"

case "$stop_reason" in
  usage_limit)
    exit 5
    ;;
  no_dependency_ready_issue)
    exit 6
    ;;
  max_iterations)
    exit 7
    ;;
  complete)
    exit 4
    ;;
  *)
    exit 4
    ;;
esac
