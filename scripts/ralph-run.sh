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
REVIEW_FEEDBACK_EVENTS_PATH=""
REVIEW_FEEDBACK_STATE_PATH=""
PROCESS_REVIEW_FEEDBACK_SWEEP="true"
REVIEW_FEEDBACK_SWEEP_CMD="scripts/review-feedback-sweep.sh"
REVIEW_FEEDBACK_STATUSES="Reviewed,Needs Review"
RETROSPECTIVE_PATH=""
PROCESS_RETROSPECTIVE="true"
RETROSPECTIVE_CMD="scripts/generate-retrospective.sh"
PROCESS_RETROSPECTIVE_IMPROVEMENTS="true"
RETROSPECTIVE_IMPROVEMENT_CMD="scripts/retrospective-to-issue-intents.sh"

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
  --review-feedback-events <path> Feedback-event JSONL path (default: .cursor/ralph/<project-slug>/review-feedback-events.jsonl)
  --review-feedback-state <path>  Feedback-sweep state path (default: .cursor/ralph/<project-slug>/review-feedback-state.json)
  --process-review-feedback-sweep <bool> Run reviewed-state sweep each iteration (default: true)
  --review-feedback-sweep-cmd <command> Sweep command (default: scripts/review-feedback-sweep.sh)
  --review-feedback-statuses <csv> Statuses considered by sweep (default: Reviewed,Needs Review)
  --retrospective <path>   Retrospective output JSON path (default: .cursor/ralph/<project-slug>/retrospective.json)
  --process-retrospective <bool> Run retrospective generation at run end (default: true)
  --retrospective-cmd <command> Retrospective generator command (default: scripts/generate-retrospective.sh)
  --process-retrospective-improvements <bool> Enqueue critical/major improvements as issue intents (default: true)
  --retrospective-improvement-cmd <command> Improvement->intent command (default: scripts/retrospective-to-issue-intents.sh)
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
    --review-feedback-events)
      shift
      REVIEW_FEEDBACK_EVENTS_PATH="${1:-}"
      ;;
    --review-feedback-state)
      shift
      REVIEW_FEEDBACK_STATE_PATH="${1:-}"
      ;;
    --process-review-feedback-sweep)
      shift
      PROCESS_REVIEW_FEEDBACK_SWEEP="${1:-}"
      ;;
    --review-feedback-sweep-cmd)
      shift
      REVIEW_FEEDBACK_SWEEP_CMD="${1:-}"
      ;;
    --review-feedback-statuses)
      shift
      REVIEW_FEEDBACK_STATUSES="${1:-}"
      ;;
    --retrospective)
      shift
      RETROSPECTIVE_PATH="${1:-}"
      ;;
    --process-retrospective)
      shift
      PROCESS_RETROSPECTIVE="${1:-}"
      ;;
    --retrospective-cmd)
      shift
      RETROSPECTIVE_CMD="${1:-}"
      ;;
    --process-retrospective-improvements)
      shift
      PROCESS_RETROSPECTIVE_IMPROVEMENTS="${1:-}"
      ;;
    --retrospective-improvement-cmd)
      shift
      RETROSPECTIVE_IMPROVEMENT_CMD="${1:-}"
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
is_bool "$PROCESS_REVIEW_FEEDBACK_SWEEP" || fail "--process-review-feedback-sweep must be true|false"
is_bool "$PROCESS_RETROSPECTIVE" || fail "--process-retrospective must be true|false"
is_bool "$PROCESS_RETROSPECTIVE_IMPROVEMENTS" || fail "--process-retrospective-improvements must be true|false"

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
if [ -z "$REVIEW_FEEDBACK_EVENTS_PATH" ]; then
  REVIEW_FEEDBACK_EVENTS_PATH=".cursor/ralph/${project_slug}/review-feedback-events.jsonl"
fi
if [ -z "$REVIEW_FEEDBACK_STATE_PATH" ]; then
  REVIEW_FEEDBACK_STATE_PATH=".cursor/ralph/${project_slug}/review-feedback-state.json"
fi
if [ -z "$RETROSPECTIVE_PATH" ]; then
  RETROSPECTIVE_PATH=".cursor/ralph/${project_slug}/retrospective.json"
fi

PROGRESS_ABS="$(abs_path "$PROGRESS_PATH")"
ASSUMPTIONS_LOG_ABS="$(abs_path "$ASSUMPTIONS_LOG_PATH")"
RESULTS_ABS="$(abs_path "$RESULTS_DIR")"
LOOP_STATE_ABS="$(abs_path "$LOOP_STATE_PATH")"
ISSUE_INTENT_QUEUE_ABS="$(abs_path "$ISSUE_INTENT_QUEUE_PATH")"
ISSUE_INTENT_RESULTS_ABS="$(abs_path "$ISSUE_INTENT_RESULTS_PATH")"
REVIEW_FEEDBACK_EVENTS_ABS="$(abs_path "$REVIEW_FEEDBACK_EVENTS_PATH")"
REVIEW_FEEDBACK_STATE_ABS="$(abs_path "$REVIEW_FEEDBACK_STATE_PATH")"
RETROSPECTIVE_ABS="$(abs_path "$RETROSPECTIVE_PATH")"

if [ -z "$RUN_LOG_PATH" ] || [ "$RUN_LOG_PATH" = "none" ]; then
  RUN_LOG_ENABLED="false"
  RUN_LOG_ABS=""
else
  RUN_LOG_ENABLED="true"
  RUN_LOG_ABS="$(abs_path "$RUN_LOG_PATH")"
fi

mkdir -p "$(dirname "$PROGRESS_ABS")" "$(dirname "$ASSUMPTIONS_LOG_ABS")" "$(dirname "$LOOP_STATE_ABS")" "$(dirname "$ISSUE_INTENT_QUEUE_ABS")" "$(dirname "$ISSUE_INTENT_RESULTS_ABS")" "$(dirname "$REVIEW_FEEDBACK_EVENTS_ABS")" "$(dirname "$REVIEW_FEEDBACK_STATE_ABS")" "$(dirname "$RETROSPECTIVE_ABS")" "$RESULTS_ABS"
if [ "$RUN_LOG_ENABLED" = "true" ]; then
  mkdir -p "$(dirname "$RUN_LOG_ABS")"
fi
touch "$PROGRESS_ABS"
touch "$ISSUE_INTENT_QUEUE_ABS" "$ISSUE_INTENT_RESULTS_ABS"
touch "$REVIEW_FEEDBACK_EVENTS_ABS"
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

read -r -a REVIEW_FEEDBACK_SWEEP_CMD_ARR <<< "$REVIEW_FEEDBACK_SWEEP_CMD"
if [ "${#REVIEW_FEEDBACK_SWEEP_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --review-feedback-sweep-cmd value"
fi
if [ "$PROCESS_REVIEW_FEEDBACK_SWEEP" = "true" ] && ! command -v "${REVIEW_FEEDBACK_SWEEP_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "review-feedback sweep command not found: ${REVIEW_FEEDBACK_SWEEP_CMD_ARR[0]}"
fi

read -r -a RETROSPECTIVE_CMD_ARR <<< "$RETROSPECTIVE_CMD"
if [ "${#RETROSPECTIVE_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --retrospective-cmd value"
fi
if [ "$PROCESS_RETROSPECTIVE" = "true" ] && ! command -v "${RETROSPECTIVE_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "retrospective command not found: ${RETROSPECTIVE_CMD_ARR[0]}"
fi

read -r -a RETROSPECTIVE_IMPROVEMENT_CMD_ARR <<< "$RETROSPECTIVE_IMPROVEMENT_CMD"
if [ "${#RETROSPECTIVE_IMPROVEMENT_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --retrospective-improvement-cmd value"
fi
if [ "$PROCESS_RETROSPECTIVE_IMPROVEMENTS" = "true" ] && ! command -v "${RETROSPECTIVE_IMPROVEMENT_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "retrospective improvement command not found: ${RETROSPECTIVE_IMPROVEMENT_CMD_ARR[0]}"
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
REVIEW_FEEDBACK_SUMMARY_JSON='{"sweeps":0,"processed_events":0,"matched_status_events":0,"requeued":0,"ignored_events":0,"invalid_events":0,"failed_sweeps":0,"requeued_issue_ids":[],"last_worker_exit_code":null}'
RETROSPECTIVE_SUMMARY_JSON='{"generated":false,"retrospective_path":null,"attempted":0,"passed":0,"failed":0,"skipped":0,"improvements_critical":0,"improvements_major":0,"improvements_minor":0,"worker_exit_code":null}'
RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON='{"considered":0,"enqueued":0,"skipped":0,"failed":0,"dedup_keys":[],"worker_exit_code":null}'

next_issue() {
  jq -c --argjson blocked "$blocked_issues_json" '
    def parse_priority($candidate):
      if ($candidate.priority | type) == "number" then $candidate.priority
      elif ($candidate.priority | type) == "object" and ($candidate.priority.value | type) == "number" then $candidate.priority.value
      else null end;

    def parse_estimate($candidate):
      if (($candidate.estimatedPoints // $candidate.estimate) | type) == "number" then ($candidate.estimatedPoints // $candidate.estimate)
      elif (($candidate.estimatedPoints // $candidate.estimate) | type) == "object"
        and (($candidate.estimatedPoints // $candidate.estimate).value | type) == "number"
      then ($candidate.estimatedPoints // $candidate.estimate).value
      else null end;

    def parse_labels($candidate):
      (
        if ($candidate.labels | type) == "array" then $candidate.labels
        elif ($candidate.linearLabels | type) == "array" then $candidate.linearLabels
        else [] end
      )
      | map(
          if type == "string" then .
          elif type == "object" then (.name // .label // .id // "") | tostring
          else tostring
          end
        )
      | map(select(length > 0));

    def parse_state($candidate):
      (
        $candidate.status // $candidate.state // $candidate.linearStatus // ""
      ) as $raw
      | if ($raw | type) == "string" then $raw
        elif ($raw | type) == "object" and ($raw.name | type) == "string" then $raw.name
        else "" end;

    .issues as $issues
    | [
        $issues[] as $candidate
        | select(($candidate.passes // false) != true)
        | ($candidate.issueId // "") as $id
        | select($id != "")
        | ($candidate.dependsOn // []) as $deps
        | parse_labels($candidate) as $labels
        | parse_state($candidate) as $state
        | (parse_priority($candidate)) as $priority
        | (parse_estimate($candidate)) as $estimate
        | (($blocked | index($id)) != null) as $blocked_in_run
        | ($deps | all(
            . as $dep
            | any($issues[]; (.issueId == $dep) and ((.passes // false) == true))
          )) as $dependency_ready
        | (($labels | index("Human Required")) != null) as $has_human_required
        | (($labels | index("Ralph")) != null) as $has_ralph
        | (($labels | index("PRD Ready")) != null) as $has_prd_ready
        | (($labels | length) > 0) as $has_labels
        | (
            if $has_labels then ($has_ralph and $has_prd_ready and ($has_human_required | not))
            else true
            end
          ) as $readiness_ready
        | (
            ($state | IN("Triage", "Needs Review", "Reviewed", "Done", "Canceled"))
            or (($state == "In Progress") and $has_human_required)
          ) as $status_blocked
        | {
            issueId: $id,
            title: ($candidate.title // ""),
            description: ($candidate.description // ""),
            estimatedPoints: $estimate,
            priority: $priority,
            linearIssueId: ($candidate.linearIssueId // null),
            sortPriority: ($priority // 999999),
            sortEstimate: ($estimate // 999999),
            exclusionReason: (
              if $blocked_in_run then "blocked_in_run"
              elif ($dependency_ready | not) then "dependency_not_ready"
              elif ($readiness_ready | not) then "readiness_not_ready"
              elif $status_blocked then "status_not_ready"
              else null end
            ),
            scheduleDecision: {
              policy: "dependency_ready -> readiness_labels -> status_gate -> priority -> estimate -> issueId",
              tuple: {
                dependency_ready: $dependency_ready,
                readiness_ready: $readiness_ready,
                status_ready: ($status_blocked | not),
                blocked_in_run: $blocked_in_run,
                priority: $priority,
                estimated_points: $estimate,
                issue_id: $id
              }
            }
          }
      ] as $all_candidates
    | ($all_candidates | map(select(.exclusionReason == null))) as $runnable
    | ($runnable | sort_by(.sortPriority, .sortEstimate, .issueId)) as $sorted
    | {
        selected: (
          ($sorted[0] // null)
          | if . == null then null else del(.sortPriority, .sortEstimate, .exclusionReason) end
        ),
        diagnostics: {
          pending_candidates: ($all_candidates | length),
          runnable_candidates: ($runnable | length),
          excluded_by_reason: {
            blocked_in_run: ($all_candidates | map(select(.exclusionReason == "blocked_in_run")) | length),
            dependency_not_ready: ($all_candidates | map(select(.exclusionReason == "dependency_not_ready")) | length),
            readiness_not_ready: ($all_candidates | map(select(.exclusionReason == "readiness_not_ready")) | length),
            status_not_ready: ($all_candidates | map(select(.exclusionReason == "status_not_ready")) | length)
          }
        }
      }
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

remove_blocked_issue() {
  local issue_id="$1"
  blocked_issues_json="$(jq -c --arg id "$issue_id" '
    [ .[] | select(. != $id) ]
  ' <<< "$blocked_issues_json")"
}

apply_review_feedback_requeues() {
  local sweep_json="$1"
  local requeue_ids_json
  local issue_id
  local tmp_prd
  local sweep_timestamp
  local applied_requeues=0
  local applied_requeue_ids='[]'
  local found_issue=0

  requeue_ids_json="$(jq -c '.requeue_issue_ids // []' <<< "$sweep_json")"
  if [ "$(jq -r 'length' <<< "$requeue_ids_json")" -eq 0 ]; then
    printf '%s\n' "$sweep_json"
    return
  fi

  while IFS= read -r issue_id; do
    [ -z "$issue_id" ] && continue
    found_issue="$(jq -r --arg id "$issue_id" '
      [ .issues[] | select((.issueId // "") == $id) ] | length
    ' "$PRD_ABS")"
    if [ "$found_issue" -eq 0 ]; then
      continue
    fi

    tmp_prd="$(mktemp)"
    jq --arg id "$issue_id" '
      .issues = (.issues | map(
        if (.issueId // "") == $id then . + {passes: false} else . end
      ))
    ' "$PRD_ABS" > "$tmp_prd"
    mv "$tmp_prd" "$PRD_ABS"

    remove_blocked_issue "$issue_id"
    applied_requeues=$((applied_requeues + 1))
    applied_requeue_ids="$(jq -c --arg id "$issue_id" '
      if index($id) == null then . + [$id] else . end
    ' <<< "$applied_requeue_ids")"

    sweep_timestamp="$(now_iso)"
    echo "RUN_FEEDBACK_REQUEUE timestamp=$sweep_timestamp issue=$issue_id reason=review_feedback" | tee -a "$PROGRESS_ABS" >/dev/null

    if [ "$RUN_LOG_ENABLED" = "true" ]; then
      jq -n -c \
        --arg timestamp "$sweep_timestamp" \
        --arg issue_id "$issue_id" \
        --argjson iteration "$iterations" \
        '
        {
          timestamp: $timestamp,
          issueId: $issue_id,
          issueTitle: null,
          iteration: $iteration,
          result: "requeued_for_feedback",
          agentCommandExitCode: null,
          contractExitCode: null,
          failureCategory: "review_feedback_requeue",
          summary: "Issue requeued due to reviewed-state feedback sweep",
          durationMs: 0,
          tokensUsed: 0,
          validationResults: {},
          filesChanged: [],
          commitHash: null,
          prUrl: null,
          retryable: false,
          handoffRequired: false
        }' >> "$RUN_LOG_ABS"
    fi
  done < <(jq -r '.[]' <<< "$requeue_ids_json")

  jq -c \
    --argjson applied_requeues "$applied_requeues" \
    --argjson applied_requeue_issue_ids "$applied_requeue_ids" \
    '. + {
      applied_requeues: $applied_requeues,
      applied_requeue_issue_ids: $applied_requeue_issue_ids
    }' <<< "$sweep_json"
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
    --arg review_feedback_events_path "$REVIEW_FEEDBACK_EVENTS_ABS" \
    --arg review_feedback_state_path "$REVIEW_FEEDBACK_STATE_ABS" \
    --arg retrospective_path "$RETROSPECTIVE_ABS" \
    --arg process_issue_intents "$PROCESS_ISSUE_INTENTS" \
    --arg issue_intent_worker_cmd "$ISSUE_INTENT_WORKER_CMD" \
    --arg process_review_feedback_sweep "$PROCESS_REVIEW_FEEDBACK_SWEEP" \
    --arg review_feedback_sweep_cmd "$REVIEW_FEEDBACK_SWEEP_CMD" \
    --arg review_feedback_statuses "$REVIEW_FEEDBACK_STATUSES" \
    --arg process_retrospective "$PROCESS_RETROSPECTIVE" \
    --arg retrospective_cmd "$RETROSPECTIVE_CMD" \
    --arg process_retrospective_improvements "$PROCESS_RETROSPECTIVE_IMPROVEMENTS" \
    --arg retrospective_improvement_cmd "$RETROSPECTIVE_IMPROVEMENT_CMD" \
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
    --argjson review_feedback_summary "$REVIEW_FEEDBACK_SUMMARY_JSON" \
    --argjson retrospective_summary "$RETROSPECTIVE_SUMMARY_JSON" \
    --argjson retrospective_improvement_summary "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON" \
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
        issue_intent_results_path: $issue_intent_results_path,
        review_feedback_events_path: $review_feedback_events_path,
        review_feedback_state_path: $review_feedback_state_path,
        retrospective_path: $retrospective_path
      },
      options: {
        max_iterations: $max_iterations,
        usage_limit: $usage_limit_num,
        autocommit: ($autocommit == "true"),
        sync_linear: ($sync_linear == "true"),
        resume: ($resume == "true"),
        stale_after_seconds: $stale_after_seconds,
        process_issue_intents: ($process_issue_intents == "true"),
        issue_intent_worker_cmd: $issue_intent_worker_cmd,
        process_review_feedback_sweep: ($process_review_feedback_sweep == "true"),
        review_feedback_sweep_cmd: $review_feedback_sweep_cmd,
        review_feedback_statuses: $review_feedback_statuses,
        process_retrospective: ($process_retrospective == "true"),
        retrospective_cmd: $retrospective_cmd,
        process_retrospective_improvements: ($process_retrospective_improvements == "true"),
        retrospective_improvement_cmd: $retrospective_improvement_cmd
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
      review_feedback: $review_feedback_summary,
      retrospective: $retrospective_summary,
      retrospective_improvements: $retrospective_improvement_summary,
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
  REVIEW_FEEDBACK_SUMMARY_JSON="$(jq -c '.review_feedback // {"sweeps":0,"processed_events":0,"matched_status_events":0,"requeued":0,"ignored_events":0,"invalid_events":0,"failed_sweeps":0,"requeued_issue_ids":[],"last_worker_exit_code":null}' "$LOOP_STATE_ABS")"
  RETROSPECTIVE_SUMMARY_JSON="$(jq -c '.retrospective // {"generated":false,"retrospective_path":null,"attempted":0,"passed":0,"failed":0,"skipped":0,"improvements_critical":0,"improvements_major":0,"improvements_minor":0,"worker_exit_code":null}' "$LOOP_STATE_ABS")"
  RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON="$(jq -c '.retrospective_improvements // {"considered":0,"enqueued":0,"skipped":0,"failed":0,"dedup_keys":[],"worker_exit_code":null}' "$LOOP_STATE_ABS")"

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

run_review_feedback_sweep() {
  local sweep_exit=0
  local sweep_output_file=""
  local sweep_output=""
  local sweep_summary=""
  local sweep_timestamp=""

  if [ "$PROCESS_REVIEW_FEEDBACK_SWEEP" != "true" ]; then
    return
  fi

  sweep_output_file="$(mktemp)"
  set +e
  "${REVIEW_FEEDBACK_SWEEP_CMD_ARR[@]}" \
    --events "$REVIEW_FEEDBACK_EVENTS_ABS" \
    --state "$REVIEW_FEEDBACK_STATE_ABS" \
    --statuses "$REVIEW_FEEDBACK_STATUSES" \
    --run-id "$RUN_ID" \
    --window-start "$RUN_STARTED_AT" \
    --window-end "$(now_iso)" > "$sweep_output_file" 2>&1
  sweep_exit=$?
  set -e

  sweep_output="$(cat "$sweep_output_file" 2>/dev/null || true)"
  rm -f "$sweep_output_file"

  if [ -n "$sweep_output" ] && jq -e '.' >/dev/null 2>&1 <<< "$sweep_output"; then
    sweep_summary="$sweep_output"
  else
    sweep_summary="$(jq -n -c \
      --arg output "$sweep_output" \
      '
      {
        processed_events: 0,
        matched_status_events: 0,
        ignored_events: 0,
        invalid_events: 0,
        requeue_issue_ids: [],
        output_parse_error: (if $output == "" then "empty sweep output" else "invalid JSON output from sweep command" end)
      }')"
    sweep_exit=31
  fi

  sweep_summary="$(apply_review_feedback_requeues "$sweep_summary")"
  sweep_timestamp="$(now_iso)"

  REVIEW_FEEDBACK_SUMMARY_JSON="$(jq -c \
    --argjson sweep "$sweep_summary" \
    --argjson worker_exit "$sweep_exit" \
    '
    {
      sweeps: (.sweeps + 1),
      processed_events: (.processed_events + ($sweep.processed_events // 0)),
      matched_status_events: (.matched_status_events + ($sweep.matched_status_events // 0)),
      requeued: (.requeued + ($sweep.applied_requeues // ($sweep.requeue_issue_ids | length // 0))),
      ignored_events: (.ignored_events + ($sweep.ignored_events // 0)),
      invalid_events: (.invalid_events + ($sweep.invalid_events // 0)),
      failed_sweeps: (.failed_sweeps + (if $worker_exit == 0 then 0 else 1 end)),
      requeued_issue_ids: ((.requeued_issue_ids + ($sweep.applied_requeue_issue_ids // [])) | unique),
      last_worker_exit_code: $worker_exit
    }' <<< "$REVIEW_FEEDBACK_SUMMARY_JSON")"

  echo "RUN_FEEDBACK_SWEEP timestamp=$sweep_timestamp processed=$(jq -r '.processed_events // 0' <<< "$sweep_summary") requeued=$(jq -r '.applied_requeues // (.requeue_issue_ids | length // 0)' <<< "$sweep_summary") ignored=$(jq -r '.ignored_events // 0' <<< "$sweep_summary") invalid=$(jq -r '.invalid_events // 0' <<< "$sweep_summary") worker_exit=$sweep_exit" | tee -a "$PROGRESS_ABS"
}

run_retrospective() {
  local retrospective_exit=0
  local retrospective_output_file=""
  local retrospective_output=""
  local retrospective_run_log="$RUN_LOG_ABS"
  local retrospective_timestamp=""

  if [ "$PROCESS_RETROSPECTIVE" != "true" ]; then
    RETROSPECTIVE_SUMMARY_JSON="$(jq -n -c \
      --arg path "$RETROSPECTIVE_ABS" \
      '
      {
        generated: false,
        retrospective_path: $path,
        attempted: 0,
        passed: 0,
        failed: 0,
        skipped: 0,
        improvements_critical: 0,
        improvements_major: 0,
        improvements_minor: 0,
        worker_exit_code: null,
        mode: "disabled"
      }')"
    return
  fi

  if [ "$RUN_LOG_ENABLED" != "true" ] || [ -z "$RUN_LOG_ABS" ]; then
    retrospective_run_log="/dev/null"
  fi

  retrospective_output_file="$(mktemp)"
  set +e
  "${RETROSPECTIVE_CMD_ARR[@]}" \
    --run-log "$retrospective_run_log" \
    --prd "$PRD_ABS" \
    --output "$RETROSPECTIVE_ABS" \
    --run-id "$RUN_ID" \
    --repo-root "$REPO_ROOT" > "$retrospective_output_file" 2>&1
  retrospective_exit=$?
  set -e

  retrospective_output="$(cat "$retrospective_output_file" 2>/dev/null || true)"
  rm -f "$retrospective_output_file"

  if [ "$retrospective_exit" -eq 0 ] && [ -n "$retrospective_output" ] && jq -e '.' >/dev/null 2>&1 <<< "$retrospective_output"; then
    RETROSPECTIVE_SUMMARY_JSON="$(jq -c --argjson worker_exit_code "$retrospective_exit" '
      . + {worker_exit_code: $worker_exit_code}
    ' <<< "$retrospective_output")"
  else
    RETROSPECTIVE_SUMMARY_JSON="$(jq -n -c \
      --arg path "$RETROSPECTIVE_ABS" \
      --arg output "$retrospective_output" \
      --argjson worker_exit_code "$retrospective_exit" \
      '
      {
        generated: false,
        retrospective_path: $path,
        attempted: 0,
        passed: 0,
        failed: 0,
        skipped: 0,
        improvements_critical: 0,
        improvements_major: 0,
        improvements_minor: 0,
        worker_exit_code: $worker_exit_code,
        mode: "generator_failure",
        worker_output: $output
      }')"
  fi

  retrospective_timestamp="$(now_iso)"
  echo "RUN_RETROSPECTIVE timestamp=$retrospective_timestamp generated=$(jq -r '.generated // false' <<< "$RETROSPECTIVE_SUMMARY_JSON") attempted=$(jq -r '.attempted // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON") failed=$(jq -r '.failed // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON") improvements_major=$(jq -r '.improvements_major // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON") worker_exit=$(jq -r '.worker_exit_code // "null"' <<< "$RETROSPECTIVE_SUMMARY_JSON")" | tee -a "$PROGRESS_ABS"
}

run_retrospective_improvements() {
  local improvement_exit=0
  local improvement_output_file=""
  local improvement_output=""
  local source_project_name=""
  local timestamp=""

  if [ "$PROCESS_RETROSPECTIVE_IMPROVEMENTS" != "true" ]; then
    RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON="$(jq -n -c '
      {
        considered: 0,
        enqueued: 0,
        skipped: 0,
        failed: 0,
        dedup_keys: [],
        worker_exit_code: null,
        mode: "disabled"
      }')"
    return
  fi

  if [ "$(jq -r '.generated // false' <<< "$RETROSPECTIVE_SUMMARY_JSON")" != "true" ] || [ ! -f "$RETROSPECTIVE_ABS" ]; then
    RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON="$(jq -n -c '
      {
        considered: 0,
        enqueued: 0,
        skipped: 0,
        failed: 0,
        dedup_keys: [],
        worker_exit_code: 0,
        mode: "no_retrospective"
      }')"
    return
  fi

  source_project_name="$(jq -r '.sourceLinearProject.name // .featureName // empty' "$PRD_ABS" 2>/dev/null || true)"

  improvement_output_file="$(mktemp)"
  set +e
  if [ -n "$source_project_name" ]; then
    "${RETROSPECTIVE_IMPROVEMENT_CMD_ARR[@]}" \
      --retrospective "$RETROSPECTIVE_ABS" \
      --queue "$ISSUE_INTENT_QUEUE_ABS" \
      --results "$ISSUE_INTENT_RESULTS_ABS" \
      --team "Studio" \
      --project "$source_project_name" > "$improvement_output_file" 2>&1
  else
    "${RETROSPECTIVE_IMPROVEMENT_CMD_ARR[@]}" \
      --retrospective "$RETROSPECTIVE_ABS" \
      --queue "$ISSUE_INTENT_QUEUE_ABS" \
      --results "$ISSUE_INTENT_RESULTS_ABS" \
      --team "Studio" > "$improvement_output_file" 2>&1
  fi
  improvement_exit=$?
  set -e

  improvement_output="$(cat "$improvement_output_file" 2>/dev/null || true)"
  rm -f "$improvement_output_file"

  if [ "$improvement_exit" -eq 0 ] && [ -n "$improvement_output" ] && jq -e '.' >/dev/null 2>&1 <<< "$improvement_output"; then
    RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON="$(jq -c --argjson worker_exit_code "$improvement_exit" '
      . + {worker_exit_code: $worker_exit_code}
    ' <<< "$improvement_output")"
  else
    RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON="$(jq -n -c \
      --arg output "$improvement_output" \
      --argjson worker_exit_code "$improvement_exit" \
      '
      {
        considered: 0,
        enqueued: 0,
        skipped: 0,
        failed: 0,
        dedup_keys: [],
        worker_exit_code: $worker_exit_code,
        mode: "pipeline_failure",
        worker_output: $output
      }')"
  fi

  timestamp="$(now_iso)"
  echo "RUN_RETROSPECTIVE_IMPROVEMENTS timestamp=$timestamp considered=$(jq -r '.considered // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON") enqueued=$(jq -r '.enqueued // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON") skipped=$(jq -r '.skipped // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON") failed=$(jq -r '.failed // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON") worker_exit=$(jq -r '.worker_exit_code // "null"' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")" | tee -a "$PROGRESS_ABS"
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
  run_review_feedback_sweep
  write_loop_state "running" "null"

  if [ -n "$USAGE_LIMIT" ] && [ "$total_tokens_used" -ge "$USAGE_LIMIT" ]; then
    stop_reason="usage_limit"
    break
  fi

  schedule_result_json="$(next_issue)"
  issue_json="$(jq -c '.selected // empty' <<< "$schedule_result_json")"
  schedule_diagnostics_json="$(jq -c '.diagnostics // {}' <<< "$schedule_result_json")"
  if [ -z "$issue_json" ]; then
    schedule_timestamp="$(now_iso)"
    echo "RUN_SCHEDULE_DECISION timestamp=$schedule_timestamp iteration=$((iterations + 1)) selected=none pending_candidates=$(jq -r '.pending_candidates // 0' <<< "$schedule_diagnostics_json") runnable_candidates=$(jq -r '.runnable_candidates // 0' <<< "$schedule_diagnostics_json") excluded_blocked=$(jq -r '.excluded_by_reason.blocked_in_run // 0' <<< "$schedule_diagnostics_json") excluded_dependency=$(jq -r '.excluded_by_reason.dependency_not_ready // 0' <<< "$schedule_diagnostics_json") excluded_readiness=$(jq -r '.excluded_by_reason.readiness_not_ready // 0' <<< "$schedule_diagnostics_json") excluded_status=$(jq -r '.excluded_by_reason.status_not_ready // 0' <<< "$schedule_diagnostics_json")" | tee -a "$PROGRESS_ABS"
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
  issue_estimated_points_json="$(jq -c '.estimatedPoints // null' <<< "$issue_json")"
  issue_priority_json="$(jq -c '.priority' <<< "$issue_json")"
  issue_schedule_decision_json="$(jq -c '.scheduleDecision // {}' <<< "$issue_json")"
  linear_issue_id="$(jq -r '.linearIssueId // empty' <<< "$issue_json")"
  safe_issue_id="${issue_id//[^A-Za-z0-9._-]/_}"
  schedule_timestamp="$(now_iso)"
  echo "RUN_SCHEDULE_DECISION timestamp=$schedule_timestamp iteration=$iterations selected=$issue_id pending_candidates=$(jq -r '.pending_candidates // 0' <<< "$schedule_diagnostics_json") runnable_candidates=$(jq -r '.runnable_candidates // 0' <<< "$schedule_diagnostics_json") excluded_blocked=$(jq -r '.excluded_by_reason.blocked_in_run // 0' <<< "$schedule_diagnostics_json") excluded_dependency=$(jq -r '.excluded_by_reason.dependency_not_ready // 0' <<< "$schedule_diagnostics_json") excluded_readiness=$(jq -r '.excluded_by_reason.readiness_not_ready // 0' <<< "$schedule_diagnostics_json") excluded_status=$(jq -r '.excluded_by_reason.status_not_ready // 0' <<< "$schedule_diagnostics_json") policy=\"$(jq -r '.policy // ""' <<< "$issue_schedule_decision_json")\" priority=$(jq -r '.tuple.priority // "null"' <<< "$issue_schedule_decision_json") estimate=$(jq -r '.tuple.estimated_points // "null"' <<< "$issue_schedule_decision_json")" | tee -a "$PROGRESS_ABS"

  payload_path="$RESULTS_ABS/${safe_issue_id}-iter-${iterations}-input.json"
  result_path="$RESULTS_ABS/${safe_issue_id}-iter-${iterations}-result.json"

  jq -n \
    --arg contract_version "1.0" \
    --argjson iteration "$iterations" \
    --arg issue_id "$issue_id" \
    --arg title "$issue_title" \
    --arg description "$issue_description" \
    --argjson estimated_points "$issue_estimated_points_json" \
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
        estimated_points: $estimated_points,
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
      --argjson estimated_points "$issue_estimated_points_json" \
      --argjson schedule_decision "$issue_schedule_decision_json" \
      --argjson schedule_diagnostics "$schedule_diagnostics_json" \
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
        estimatedPoints: $estimated_points,
        scheduleDecision: $schedule_decision,
        scheduleDiagnostics: $schedule_diagnostics,
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
    --argjson schedule_decision "$issue_schedule_decision_json" \
    --argjson schedule_diagnostics "$schedule_diagnostics_json" \
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
      schedule_decision: $schedule_decision,
      schedule_diagnostics: $schedule_diagnostics,
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
feedback_sweeps="$(jq -r '.sweeps // 0' <<< "$REVIEW_FEEDBACK_SUMMARY_JSON")"
feedback_requeued="$(jq -r '.requeued // 0' <<< "$REVIEW_FEEDBACK_SUMMARY_JSON")"
feedback_failed_sweeps="$(jq -r '.failed_sweeps // 0' <<< "$REVIEW_FEEDBACK_SUMMARY_JSON")"
feedback_requeue_ids="$(jq -r '.requeued_issue_ids // [] | join(",")' <<< "$REVIEW_FEEDBACK_SUMMARY_JSON")"

if [ "$pending_remaining" -gt 0 ] && [ "$iterations" -ge "$MAX_ITERATIONS" ] && [ "$stop_reason" = "complete" ]; then
  stop_reason="max_iterations"
fi

run_retrospective
retrospective_generated="$(jq -r '.generated // false' <<< "$RETROSPECTIVE_SUMMARY_JSON")"
retrospective_attempted="$(jq -r '.attempted // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON")"
retrospective_failed="$(jq -r '.failed // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON")"
retrospective_improvements_major="$(jq -r '.improvements_major // 0' <<< "$RETROSPECTIVE_SUMMARY_JSON")"
retrospective_worker_exit="$(jq -r '.worker_exit_code // "null"' <<< "$RETROSPECTIVE_SUMMARY_JSON")"

run_retrospective_improvements
retrospective_improvements_considered="$(jq -r '.considered // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")"
retrospective_improvements_enqueued="$(jq -r '.enqueued // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")"
retrospective_improvements_skipped="$(jq -r '.skipped // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")"
retrospective_improvements_failed="$(jq -r '.failed // 0' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")"
retrospective_improvements_worker_exit="$(jq -r '.worker_exit_code // "null"' <<< "$RETROSPECTIVE_IMPROVEMENT_SUMMARY_JSON")"

run_issue_intent_worker
issue_intent_processed="$(jq -r '.processed // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_created="$(jq -r '.created // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_failed="$(jq -r '.failed // 0' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_worker_exit="$(jq -r '.worker_exit_code // "null"' <<< "$ISSUE_INTENT_SUMMARY_JSON")"
issue_intent_created_ids="$(jq -r '.created_issue_ids // [] | join(",")' <<< "$ISSUE_INTENT_SUMMARY_JSON")"

echo "RUN_ISSUE_INTENTS timestamp=$(now_iso) processed=$issue_intent_processed created=$issue_intent_created failed=$issue_intent_failed worker_exit=$issue_intent_worker_exit created_issue_ids=$issue_intent_created_ids" | tee -a "$PROGRESS_ABS"
echo "RUN_COMPLETE timestamp=$(now_iso) iterations=$iterations completed=$completed_count pending=$pending_remaining stop_reason=$stop_reason tokens_used=$total_tokens_used feedback_sweeps=$feedback_sweeps feedback_requeued=$feedback_requeued feedback_failed_sweeps=$feedback_failed_sweeps feedback_requeue_issue_ids=$feedback_requeue_ids retrospective_generated=$retrospective_generated retrospective_attempted=$retrospective_attempted retrospective_failed=$retrospective_failed retrospective_improvements_major=$retrospective_improvements_major retrospective_worker_exit=$retrospective_worker_exit retrospective_improvements_considered=$retrospective_improvements_considered retrospective_improvements_enqueued=$retrospective_improvements_enqueued retrospective_improvements_skipped=$retrospective_improvements_skipped retrospective_improvements_failed=$retrospective_improvements_failed retrospective_improvements_worker_exit=$retrospective_improvements_worker_exit issue_intents_processed=$issue_intent_processed issue_intents_created=$issue_intent_created issue_intents_failed=$issue_intent_failed" | tee -a "$PROGRESS_ABS"

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
