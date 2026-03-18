#!/usr/bin/env bash
#
# Generate a deterministic morning briefing from Ralph runtime artifacts.
# Aggregates run-log, retrospective, progress, and PRD data into a single
# developer-facing markdown view with optional JSON sidecar.
#

set -euo pipefail

RUN_LOG_PATH=""
RETROSPECTIVE_PATH=""
PROGRESS_PATH=""
PRD_PATH=""
OUTPUT_PATH=""
JSON_PATH=""
PROJECT_SLUG=""
RUN_ID=""

usage() {
  cat <<'USAGE'
Usage: scripts/generate-morning-briefing.sh [options]

Options:
  --run-log <path>        Path to run-log.jsonl (required)
  --retrospective <path>  Path to retrospective.json (optional)
  --progress <path>       Path to progress.txt (optional)
  --prd <path>            Path to prd.json for project state (optional)
  --output <path>         Output markdown briefing path (required)
  --json <path>           JSON sidecar output path (optional)
  --project-slug <slug>   Derive default retrospective/prd paths (optional)
  --run-id <id>           Run identifier for traceability (optional)
  --help                  Show this help
USAGE
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --run-log) shift; RUN_LOG_PATH="${1:-}" ;;
    --retrospective) shift; RETROSPECTIVE_PATH="${1:-}" ;;
    --progress) shift; PROGRESS_PATH="${1:-}" ;;
    --prd) shift; PRD_PATH="${1:-}" ;;
    --output) shift; OUTPUT_PATH="${1:-}" ;;
    --json) shift; JSON_PATH="${1:-}" ;;
    --project-slug) shift; PROJECT_SLUG="${1:-}" ;;
    --run-id) shift; RUN_ID="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$RUN_LOG_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [ ! -f "$RUN_LOG_PATH" ]; then
  echo "run-log not found: $RUN_LOG_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Derive default paths from --project-slug when explicit paths not given
# ---------------------------------------------------------------------------

if [ -n "$PROJECT_SLUG" ]; then
  if [ -z "$RETROSPECTIVE_PATH" ]; then
    candidate=".cursor/ralph/${PROJECT_SLUG}/retrospective.json"
    if [ -f "$candidate" ]; then
      RETROSPECTIVE_PATH="$candidate"
    fi
  fi
  if [ -z "$PRD_PATH" ]; then
    candidate=".cursor/ralph/${PROJECT_SLUG}/prd.json"
    if [ -f "$candidate" ]; then
      PRD_PATH="$candidate"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Parse inputs
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "$OUTPUT_PATH")"
if [ -n "$JSON_PATH" ]; then
  mkdir -p "$(dirname "$JSON_PATH")"
fi

run_log_json="$(jq -Rsc '
  split("\n")
  | map(select(length > 0))
  | map(fromjson? // {"_invalid": true})
  | map(select(type == "object" and (._invalid // false) != true))
' "$RUN_LOG_PATH")"

retrospective_json='null'
if [ -n "$RETROSPECTIVE_PATH" ] && [ -f "$RETROSPECTIVE_PATH" ]; then
  retrospective_json="$(jq -c '.' "$RETROSPECTIVE_PATH")"
fi

prd_json='null'
if [ -n "$PRD_PATH" ] && [ -f "$PRD_PATH" ]; then
  prd_json="$(jq -c '.' "$PRD_PATH")"
fi

# Parse run window from progress.txt
window_start=""
window_end=""
if [ -n "$PROGRESS_PATH" ] && [ -f "$PROGRESS_PATH" ]; then
  window_json="$(jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | map(capture("^(?<marker>RUN_START|RUN_COMPLETE).*timestamp=(?<timestamp>[^[:space:]]+)")?)
    | map(select(. != null))
    | {
        start: (map(select(.marker == "RUN_START") | .timestamp) | last),
        end: (map(select(.marker == "RUN_COMPLETE") | .timestamp) | last)
      }
  ' "$PROGRESS_PATH")"
  window_start="$(jq -r '.start // ""' <<< "$window_json")"
  window_end="$(jq -r '.end // ""' <<< "$window_json")"
fi

generated_at="$(now_iso)"

# ---------------------------------------------------------------------------
# Build the sidecar JSON with all six sections
# ---------------------------------------------------------------------------

sidecar_json="$(jq -n -c \
  --arg generated_at "$generated_at" \
  --arg run_log_path "$RUN_LOG_PATH" \
  --arg retrospective_path "$RETROSPECTIVE_PATH" \
  --arg progress_path "$PROGRESS_PATH" \
  --arg prd_path "$PRD_PATH" \
  --arg project_slug "$PROJECT_SLUG" \
  --arg run_id "$RUN_ID" \
  --arg window_start "$window_start" \
  --arg window_end "$window_end" \
  --argjson run_log "$run_log_json" \
  --argjson retrospective "$retrospective_json" \
  --argjson prd "$prd_json" \
  '
  def normalize_result($value):
    if $value == "passed" then "success"
    elif $value == "failed" then "failure"
    else $value
    end;

  def to_epoch($value):
    if ($value | type) == "string" then (try ($value | fromdateiso8601) catch null)
    else null
    end;

  def fmt_duration_ms($ms):
    if $ms == null or $ms == 0 then "0s"
    elif $ms < 60000 then "\(($ms / 1000 | floor))s"
    else "\(($ms / 60000 | floor))m \((($ms % 60000) / 1000 | floor))s"
    end;

  # Normalize all entries
  ($run_log
    | map(. + {
        norm_result: normalize_result(.result // .outcome // ""),
        norm_issue_id: (.issueId // .issue_id // ""),
        norm_issue_title: (.issueTitle // .issue_title // ""),
        timestamp_epoch: to_epoch(.timestamp // null)
      })
  ) as $all_entries

  # Window-filter if progress timestamps are available
  | (to_epoch($window_start)) as $ws_epoch
  | (to_epoch($window_end)) as $we_epoch
  | (
      if ($ws_epoch != null and $we_epoch != null) then
        $all_entries | map(select(.timestamp_epoch != null and .timestamp_epoch >= $ws_epoch and .timestamp_epoch <= $we_epoch))
      else
        $all_entries
      end
    ) as $window_entries

  | ($window_entries | map(select(.norm_result != "requeued_for_feedback"))) as $attempt_entries
  | ($attempt_entries | map(select(.norm_result == "success")) | length) as $success_count
  | ($attempt_entries | map(select(.norm_result == "failure")) | length) as $failure_count
  | ($attempt_entries | map(select(.norm_result == "human_required")) | length) as $human_required_count
  | ($attempt_entries | map(select((.retryable // false) == true and .norm_result == "failure")) | length) as $retryable_count

  # Aggregate files changed
  | ($attempt_entries
      | map((.filesChanged // .files_changed // []))
      | add // []
      | map(select(type == "string" and length > 0))
      | unique
    ) as $changed_files

  | ($changed_files
      | map(split("/") | .[0:2] | join("/"))
      | group_by(.)
      | map({area: .[0], count: length})
      | sort_by((.count * -1), .area)
    ) as $changed_area_rows

  # Token usage
  | ($attempt_entries | map(.tokensUsed // .tokens_used // 0) | add // 0) as $total_tokens
  | ($attempt_entries | map(.durationMs // .duration_ms // 0) | add // 0) as $total_duration_ms

  # Token usage from retrospective if available
  | (if $retrospective != null then ($retrospective.tokenUsageAggregate // {}) else {} end) as $retro_tokens

  # -----------------------------------------------------------------------
  # Section 1: Overnight Summary
  # -----------------------------------------------------------------------

  | {
      overnight_summary: {
        run_window: {
          start: (if $window_start == "" then null else $window_start end),
          end: (if $window_end == "" then null else $window_end end)
        },
        iterations_executed: ($attempt_entries | length),
        success_count: $success_count,
        failure_count: $failure_count,
        human_required_count: $human_required_count,
        retryable_failure_count: $retryable_count,
        total_files_changed: ($changed_files | length),
        changed_files: $changed_files,
        changed_areas: $changed_area_rows,
        total_tokens_used: $total_tokens,
        total_duration_ms: $total_duration_ms,
        retro_token_aggregate: (if ($retro_tokens | length) > 0 then $retro_tokens else null end)
      }
    } as $sec_summary

  # -----------------------------------------------------------------------
  # Section 2: Issue Outcomes
  # -----------------------------------------------------------------------

  | ($attempt_entries
      | sort_by(.norm_issue_id)
      | group_by(.norm_issue_id)
      | map(select((.[0].norm_issue_id) != ""))
      | map(
          (.[0].norm_issue_id) as $iid
          | {
              issue_id: $iid,
              issue_title: (.[0].norm_issue_title),
              attempts: length,
              final_outcome: (.[-1].norm_result // "unknown"),
              total_duration_ms: (map(.durationMs // .duration_ms // 0) | add),
              total_tokens: (map(.tokensUsed // .tokens_used // 0) | add),
              files_changed: (map(.filesChanged // .files_changed // []) | add // [] | unique),
              retryable: (any(.[]; (.retryable // false) == true)),
              handoff_required: (any(.[]; (.handoffRequired // .handoff_required // false) == true)),
              failure_category: (.[-1].failureCategory // .[-1].failure_category // null),
              summary: (.[-1].summary // "")
            }
        )
    ) as $issue_outcomes_all

  | ($issue_outcomes_all | map(select(.final_outcome == "success"))) as $completed_issues
  | ($issue_outcomes_all | map(select(.final_outcome == "human_required" or .handoff_required == true))) as $needs_review_issues
  | ($issue_outcomes_all | map(select(.final_outcome == "failure"))) as $failed_issues
  | ($issue_outcomes_all | map(select(.final_outcome != "success" and .final_outcome != "failure" and .final_outcome != "human_required" and .handoff_required != true))) as $other_issues

  | ($sec_summary + {
      issue_outcomes: {
        all: $issue_outcomes_all,
        completed: $completed_issues,
        needs_review: $needs_review_issues,
        blocked_failed: $failed_issues,
        other: $other_issues
      }
    }) as $sec_outcomes

  # -----------------------------------------------------------------------
  # Section 3: Decision Queue
  # -----------------------------------------------------------------------

  | ($issue_outcomes_all
      | map(select(
          .final_outcome == "human_required"
          or .handoff_required == true
          or .final_outcome == "failure"
        ))
      | sort_by(
          (if .final_outcome == "human_required" or .handoff_required == true then 0 else 1 end),
          (.issue_id)
        )
      | map({
          issue_id: .issue_id,
          issue_title: .issue_title,
          outcome: .final_outcome,
          blocker_reason: (
            if .failure_category != null and .failure_category != "none" and .failure_category != ""
            then .failure_category
            else null
            end
          ),
          summary: .summary,
          retryable: .retryable,
          attempts: .attempts
        })
    ) as $decision_queue

  | ($sec_outcomes + { decision_queue: $decision_queue }) as $sec_decisions

  # -----------------------------------------------------------------------
  # Section 4: Project State (from PRD if available)
  # -----------------------------------------------------------------------

  | (if $prd != null then
      ($prd.issues // []) as $prd_issues
      | ($prd_issues | length) as $total_prd_issues
      | ($issue_outcomes_all | map(select(.final_outcome == "success")) | map(.issue_id)) as $done_ids
      | ($prd_issues | map(select((.issueId // .issue_id // "") as $pid | ($done_ids | map(select(. == $pid)) | length) == 0))) as $remaining_issues
      | ($remaining_issues | map(.estimate // .estimatedPoints // 0) | add // 0) as $remaining_effort
      | ($remaining_issues | map(select((.dependencies // []) | length > 0))
          | map({
              issue_id: (.issueId // .issue_id // ""),
              title: (.title // ""),
              blocked_by: (.dependencies // [])
            })
        ) as $dep_blockers
      | {
          total_prd_issues: $total_prd_issues,
          completed_count: ($done_ids | length),
          remaining_count: ($remaining_issues | length),
          remaining_estimated_points: $remaining_effort,
          dependency_blockers: $dep_blockers,
          remaining_issues: ($remaining_issues | map({
            issue_id: (.issueId // .issue_id // ""),
            title: (.title // ""),
            priority: (.priority // null),
            estimate: (.estimate // .estimatedPoints // null),
            readiness: (.readiness // .readinessStatus // null)
          }))
        }
    else
      {
        total_prd_issues: null,
        completed_count: null,
        remaining_count: null,
        remaining_estimated_points: null,
        dependency_blockers: [],
        remaining_issues: []
      }
    end
  ) as $project_state

  | ($sec_decisions + { project_state: $project_state }) as $sec_project

  # -----------------------------------------------------------------------
  # Section 5: Risk Flags
  # -----------------------------------------------------------------------

  | (
      []
      + ($issue_outcomes_all
          | map(select(.attempts > 1))
          | map({ flag: "multiple_retries", issue_id: .issue_id, detail: "\(.issue_id) required \(.attempts) attempts" })
        )
      + ($attempt_entries
          | map(select(
              (.validationResults // .validation_results // {})
              | to_entries
              | any(.value == "fail" or .value == "failed")
            ))
          | map({ flag: "failed_validation", issue_id: (.norm_issue_id), detail: "\(.norm_issue_id) had failed validation checks" })
          | unique_by(.issue_id)
        )
      + (if $retrospective != null then
          ($retrospective.proposedImprovements // [])
          | map(select(.severity == "critical" or .severity == "major"))
          | map({ flag: "retrospective_\(.severity)", issue_id: null, detail: "\(.severity): \(.observation)" })
        else [] end)
      + ($attempt_entries
          | map(select((.executionIncident // "") != ""))
          | map({ flag: "execution_incident", issue_id: (.norm_issue_id), detail: "\(.norm_issue_id): \(.executionIncident)" })
        )
    ) as $risk_flags

  | ($sec_project + { risk_flags: $risk_flags }) as $sec_risks

  # -----------------------------------------------------------------------
  # Section 6: Recommended Actions
  # -----------------------------------------------------------------------

  | (
      []
      + ($decision_queue
          | map(select(.outcome == "human_required" or (.retryable // false) == false))
          | map({ priority: 1, action: "Review \(.issue_id): \(.summary)", issue_id: .issue_id })
        )
      + ($decision_queue
          | map(select((.retryable // false) == true))
          | map({ priority: 2, action: "Retry \(.issue_id) (retryable failure)", issue_id: .issue_id })
        )
      + (if ($risk_flags | map(select(.flag == "failed_validation")) | length) > 0 then
          [{ priority: 2, action: "Investigate failed validations", issue_id: null }]
        else [] end)
      + (if ($risk_flags | map(select(.flag | startswith("retrospective_"))) | length) > 0 then
          [{ priority: 3, action: "Address retrospective improvements (see risk flags)", issue_id: null }]
        else [] end)
      + (if $project_state.dependency_blockers != null and ($project_state.dependency_blockers | length) > 0 then
          [{ priority: 3, action: "Resolve dependency blockers before next run", issue_id: null }]
        else [] end)
      | sort_by(.priority, .issue_id)
    ) as $recommended_actions

  | ($sec_risks + { recommended_actions: $recommended_actions }) as $full

  # -----------------------------------------------------------------------
  # Final envelope
  # -----------------------------------------------------------------------

  | {
      contract_version: "1.0",
      generated_at: $generated_at,
      run_id: (if $run_id == "" then null else $run_id end),
      source: {
        run_log_path: $run_log_path,
        retrospective_path: (if $retrospective_path == "" then null else $retrospective_path end),
        progress_path: (if $progress_path == "" then null else $progress_path end),
        prd_path: (if $prd_path == "" then null else $prd_path end),
        project_slug: (if $project_slug == "" then null else $project_slug end)
      },
      overnight_summary: $full.overnight_summary,
      issue_outcomes: $full.issue_outcomes,
      decision_queue: $full.decision_queue,
      project_state: $full.project_state,
      risk_flags: $full.risk_flags,
      recommended_actions: $full.recommended_actions
    }
  ')"

# ---------------------------------------------------------------------------
# Write JSON sidecar if requested
# ---------------------------------------------------------------------------

if [ -n "$JSON_PATH" ]; then
  printf '%s\n' "$sidecar_json" > "$JSON_PATH"
fi

# ---------------------------------------------------------------------------
# Emit markdown briefing
# ---------------------------------------------------------------------------

{
  echo "# Morning Briefing"
  echo
  echo "_Generated at $(jq -r '.generated_at' <<< "$sidecar_json")_"
  if [ -n "$RUN_ID" ]; then
    printf '\n_Run ID: `%s`_\n' "$RUN_ID"
  fi
  echo
  echo "**Sources:** \`${RUN_LOG_PATH}\`"
  [ -n "$RETROSPECTIVE_PATH" ] && [ -f "$RETROSPECTIVE_PATH" ] && printf ', `%s`' "$RETROSPECTIVE_PATH"
  [ -n "$PROGRESS_PATH" ] && [ -f "$PROGRESS_PATH" ] && printf ', `%s`' "$PROGRESS_PATH"
  [ -n "$PRD_PATH" ] && [ -f "$PRD_PATH" ] && printf ', `%s`' "$PRD_PATH"
  echo

  # ------ Section 1: Overnight Summary ------
  echo
  echo "## 1. Overnight Summary"
  echo
  run_win_start="$(jq -r '.overnight_summary.run_window.start // "n/a"' <<< "$sidecar_json")"
  run_win_end="$(jq -r '.overnight_summary.run_window.end // "n/a"' <<< "$sidecar_json")"
  printf -- '- **Run window:** `%s` to `%s`\n' "$run_win_start" "$run_win_end"
  echo
  echo "| Metric | Value |"
  echo "| --- | --- |"
  echo "| Iterations executed | $(jq -r '.overnight_summary.iterations_executed' <<< "$sidecar_json") |"
  echo "| Passed | $(jq -r '.overnight_summary.success_count' <<< "$sidecar_json") |"
  echo "| Failed | $(jq -r '.overnight_summary.failure_count' <<< "$sidecar_json") |"
  echo "| Human required | $(jq -r '.overnight_summary.human_required_count' <<< "$sidecar_json") |"
  echo "| Files changed | $(jq -r '.overnight_summary.total_files_changed' <<< "$sidecar_json") |"
  total_tokens="$(jq -r '.overnight_summary.total_tokens_used' <<< "$sidecar_json")"
  if [ "$total_tokens" != "0" ]; then
    echo "| Tokens used | ${total_tokens} |"
  fi
  total_dur="$(jq -r '.overnight_summary.total_duration_ms' <<< "$sidecar_json")"
  if [ "$total_dur" != "0" ]; then
    dur_display="$(jq -rn --argjson ms "$total_dur" 'if $ms < 60000 then "\($ms / 1000 | floor)s" else "\($ms / 60000 | floor)m \(($ms % 60000) / 1000 | floor)s" end')"
    echo "| Total duration | ${dur_display} |"
  fi

  area_count="$(jq -r '.overnight_summary.changed_areas | length' <<< "$sidecar_json")"
  if [ "$area_count" != "0" ]; then
    echo
    echo "### Changed Areas"
    echo
    echo "| Area | Files |"
    echo "| --- | --- |"
    jq -r '.overnight_summary.changed_areas[] | "| `\(.area)` | \(.count) |"' <<< "$sidecar_json"
  fi

  # ------ Section 2: Issue Outcomes ------
  echo
  echo "## 2. Issue Outcomes"
  echo

  outcome_count="$(jq -r '.issue_outcomes.all | length' <<< "$sidecar_json")"
  if [ "$outcome_count" = "0" ]; then
    echo "No issue outcomes recorded."
  else
    completed_count="$(jq -r '.issue_outcomes.completed | length' <<< "$sidecar_json")"
    if [ "$completed_count" != "0" ]; then
      echo "### Completed ($completed_count)"
      echo
      echo "| Issue | Title | Duration | Tokens |"
      echo "| --- | --- | --- | --- |"
      jq -r '.issue_outcomes.completed[] |
        .total_duration_ms as $ms |
        (if $ms < 60000 then "\($ms / 1000 | floor)s" else "\($ms / 60000 | floor)m" end) as $dur |
        "| `\(.issue_id)` | \(.issue_title) | \($dur) | \(.total_tokens) |"
      ' <<< "$sidecar_json"
      echo
    fi

    needs_review_count="$(jq -r '.issue_outcomes.needs_review | length' <<< "$sidecar_json")"
    if [ "$needs_review_count" != "0" ]; then
      echo "### Needs Review ($needs_review_count)"
      echo
      echo "| Issue | Title | Outcome | Duration |"
      echo "| --- | --- | --- | --- |"
      jq -r '.issue_outcomes.needs_review[] |
        .total_duration_ms as $ms |
        (if $ms < 60000 then "\($ms / 1000 | floor)s" else "\($ms / 60000 | floor)m" end) as $dur |
        "| `\(.issue_id)` | \(.issue_title) | `\(.final_outcome)` | \($dur) |"
      ' <<< "$sidecar_json"
      echo
    fi

    failed_count="$(jq -r '.issue_outcomes.blocked_failed | length' <<< "$sidecar_json")"
    if [ "$failed_count" != "0" ]; then
      echo "### Blocked / Failed ($failed_count)"
      echo
      echo "| Issue | Title | Category | Retryable | Attempts |"
      echo "| --- | --- | --- | --- | --- |"
      jq -r '.issue_outcomes.blocked_failed[] |
        "| `\(.issue_id)` | \(.issue_title) | `\(.failure_category // "unknown")` | \(.retryable) | \(.attempts) |"
      ' <<< "$sidecar_json"
      echo
    fi
  fi

  # ------ Section 3: Decision Queue ------
  echo "## 3. Decision Queue"
  echo

  dq_count="$(jq -r '.decision_queue | length' <<< "$sidecar_json")"
  if [ "$dq_count" = "0" ]; then
    echo "No issues require human input."
  else
    echo "Issues needing human decision, sorted by urgency:"
    echo
    echo "| # | Issue | Outcome | Blocker / Reason | Summary |"
    echo "| --- | --- | --- | --- | --- |"
    jq -r '
      .decision_queue | to_entries[] |
      "\(.key + 1)" as $idx |
      .value |
      "| \($idx) | `\(.issue_id)` | `\(.outcome)` | \(.blocker_reason // "—") | \(.summary | if length > 80 then .[:80] + "…" else . end) |"
    ' <<< "$sidecar_json"
  fi

  # ------ Section 4: Project State ------
  echo
  echo "## 4. Project State"
  echo

  prd_available="$(jq -r '.project_state.total_prd_issues // "null"' <<< "$sidecar_json")"
  if [ "$prd_available" = "null" ]; then
    echo 'No PRD provided — project state unavailable. Pass `--prd <path>` for this section.'
  else
    total_prd="$(jq -r '.project_state.total_prd_issues' <<< "$sidecar_json")"
    completed_prd="$(jq -r '.project_state.completed_count' <<< "$sidecar_json")"
    remaining_prd="$(jq -r '.project_state.remaining_count' <<< "$sidecar_json")"
    remaining_pts="$(jq -r '.project_state.remaining_estimated_points' <<< "$sidecar_json")"

    echo "| Metric | Value |"
    echo "| --- | --- |"
    echo "| Total PRD issues | ${total_prd} |"
    echo "| Completed | ${completed_prd} |"
    echo "| Remaining | ${remaining_prd} |"
    echo "| Remaining estimated points | ${remaining_pts} |"

    dep_count="$(jq -r '.project_state.dependency_blockers | length' <<< "$sidecar_json")"
    if [ "$dep_count" != "0" ]; then
      echo
      echo "### Dependency Blockers"
      echo
      jq -r '.project_state.dependency_blockers[] |
        "- `\(.issue_id)` (\(.title)) blocked by: \(.blocked_by | join(", "))"
      ' <<< "$sidecar_json"
    fi
  fi

  # ------ Section 5: Risk Flags ------
  echo
  echo "## 5. Risk Flags"
  echo

  risk_count="$(jq -r '.risk_flags | length' <<< "$sidecar_json")"
  if [ "$risk_count" = "0" ]; then
    echo "No elevated risk flags."
  else
    jq -r '.risk_flags[] | "- **\(.flag)**: \(.detail)"' <<< "$sidecar_json"
  fi

  # ------ Section 6: Recommended Actions ------
  echo
  echo "## 6. Recommended Actions"
  echo

  action_count="$(jq -r '.recommended_actions | length' <<< "$sidecar_json")"
  if [ "$action_count" = "0" ]; then
    echo "No recommended actions — all clear."
  else
    jq -r '.recommended_actions | to_entries[] | "\(.key + 1). \(.value.action)"' <<< "$sidecar_json"
  fi
} > "$OUTPUT_PATH"

# ---------------------------------------------------------------------------
# Summary JSON to stdout
# ---------------------------------------------------------------------------

jq -n -c \
  --arg output "$OUTPUT_PATH" \
  --arg json_path "${JSON_PATH:-}" \
  --argjson doc "$sidecar_json" \
  '{
    generated: true,
    markdown_path: $output,
    json_path: (if $json_path == "" then null else $json_path end),
    iterations_executed: ($doc.overnight_summary.iterations_executed // 0),
    success_count: ($doc.overnight_summary.success_count // 0),
    failure_count: ($doc.overnight_summary.failure_count // 0),
    human_required_count: ($doc.overnight_summary.human_required_count // 0),
    decision_queue_count: (($doc.decision_queue // []) | length),
    risk_flag_count: (($doc.risk_flags // []) | length),
    recommended_action_count: (($doc.recommended_actions // []) | length)
  }'
