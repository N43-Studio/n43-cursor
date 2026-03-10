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
AGENT_CMD="scripts/mock-issue-agent.sh"
WORKDIR="$REPO_ROOT"
PROGRESS_PATH="progress.txt"
RUN_LOG_PATH="run-log.jsonl"
ASSUMPTIONS_LOG_PATH="assumptions-log.jsonl"
RESULTS_DIR=".ralph/results"

usage() {
  cat <<'EOF'
Usage: scripts/ralph-run.sh --prd <path> [options]

Options:
  --prd <path>          Path to prd.json (required)
  --max <number>        Maximum iterations (default: 5)
  --usage-limit <num>   Stop when cumulative tokens_used >= limit
  --autocommit <bool>   true|false (default: true)
  --sync-linear <bool>  true|false (default: false)
  --agent-cmd <command> CLI command for one issue run (default: scripts/mock-issue-agent.sh)
  --workdir <path>      Working directory for issue execution (default: repo root)
  --progress <path>     Progress output path (default: progress.txt)
  --run-log <path>      JSONL run log path (default: run-log.jsonl)
  --assumptions-log <path>  JSONL assumptions log path (default: assumptions-log.jsonl)
  --results-dir <path>  Directory for input/output payload artifacts (default: .ralph/results)
  --help                Show this help
EOF
}

fail() {
  echo "ERROR: $1" >&2
  exit "${2:-1}"
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

require_cmd jq

if [ ! -f "$PRD_PATH" ]; then
  fail "PRD not found: $PRD_PATH"
fi

if [ ! -d "$WORKDIR" ]; then
  fail "workdir not found: $WORKDIR"
fi

PRD_ABS="$(abs_path "$PRD_PATH")"
PROGRESS_ABS="$(abs_path "$PROGRESS_PATH")"
RUN_LOG_ABS="$(abs_path "$RUN_LOG_PATH")"
ASSUMPTIONS_LOG_ABS="$(abs_path "$ASSUMPTIONS_LOG_PATH")"
RESULTS_ABS="$(abs_path "$RESULTS_DIR")"

mkdir -p "$(dirname "$PROGRESS_ABS")" "$(dirname "$RUN_LOG_ABS")" "$(dirname "$ASSUMPTIONS_LOG_ABS")" "$RESULTS_ABS"
touch "$PROGRESS_ABS" "$RUN_LOG_ABS"

# Split command by shell words; keep agent command simple and deterministic.
read -r -a AGENT_CMD_ARR <<< "$AGENT_CMD"
if [ "${#AGENT_CMD_ARR[@]}" -eq 0 ]; then
  fail "invalid --agent-cmd value"
fi
if ! command -v "${AGENT_CMD_ARR[0]}" >/dev/null 2>&1; then
  fail "agent command not found: ${AGENT_CMD_ARR[0]}"
fi

if ! jq -e '.issues | type == "array"' "$PRD_ABS" >/dev/null; then
  fail "PRD must include an issues array"
fi

blocked_issues_json='[]'
iterations=0
total_tokens_used=0
stop_reason="complete"

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

echo "Ralph run start: prd=$PRD_ABS max=$MAX_ITERATIONS" | tee -a "$PROGRESS_ABS"

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

  jq -n -c \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
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

  echo "iteration=$iterations issue=$issue_id outcome=$outcome retryable=$retryable handoff=$handoff_required" | tee -a "$PROGRESS_ABS"

  if [ "$outcome" = "success" ]; then
    tmp_prd="$(mktemp)"
    jq --arg id "$issue_id" '
      .issues = (.issues | map(
        if .issueId == $id then . + {passes: true} else . end
      ))
    ' "$PRD_ABS" > "$tmp_prd"
    mv "$tmp_prd" "$PRD_ABS"
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
    continue
  fi

  if [ "$retryable" = "false" ]; then
    add_blocked_issue "$issue_id"
  fi
done

pending_remaining="$(pending_count)"
completed_count="$(jq '[.issues[] | select((.passes // false) == true)] | length' "$PRD_ABS")"

echo "Ralph run complete: iterations=$iterations completed=$completed_count pending=$pending_remaining stop_reason=$stop_reason tokens_used=$total_tokens_used" | tee -a "$PROGRESS_ABS"

if [ "$pending_remaining" -eq 0 ]; then
  exit 0
fi

case "$stop_reason" in
  usage_limit)
    exit 5
    ;;
  no_dependency_ready_issue)
    exit 6
    ;;
  complete)
    exit 4
    ;;
  *)
    exit 4
    ;;
esac
