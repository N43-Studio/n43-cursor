#!/usr/bin/env bash
#
# Generate deterministic retrospective analysis from run-log and PRD artifacts.
#

set -euo pipefail

RUN_LOG_PATH=""
PRD_PATH=""
OUTPUT_PATH=""
RUN_ID=""
REPO_ROOT="$(pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/generate-retrospective.sh [options]

Options:
  --run-log <path>   Path to run-log.jsonl (required)
  --prd <path>       Path to prd.json (required)
  --output <path>    Output retrospective.json path (required)
  --run-id <id>      Run identifier for traceability (optional)
  --repo-root <path> Repo root for git context (default: cwd)
  --help             Show this help
USAGE
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --run-log) shift; RUN_LOG_PATH="${1:-}" ;;
    --prd) shift; PRD_PATH="${1:-}" ;;
    --output) shift; OUTPUT_PATH="${1:-}" ;;
    --run-id) shift; RUN_ID="${1:-}" ;;
    --repo-root) shift; REPO_ROOT="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$RUN_LOG_PATH" ] || [ -z "$PRD_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [ ! -f "$PRD_PATH" ]; then
  echo "prd not found: $PRD_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
if [ ! -f "$RUN_LOG_PATH" ]; then
  touch "$RUN_LOG_PATH"
fi

entries_json="$(jq -Rsc '
  split("\n")
  | map(select(length > 0))
  | map(fromjson? // {"_invalid": true})
  | map(select(type == "object" and (._invalid // false) != true))
' "$RUN_LOG_PATH")"

git_commits_json='[]'
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_commits_json="$(git -C "$REPO_ROOT" log --oneline -n 10 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')"
fi

generated_at="$(now_iso)"

retrospective_json="$(jq -n -c \
  --arg generated_at "$generated_at" \
  --arg run_id "$RUN_ID" \
  --arg run_log_path "$RUN_LOG_PATH" \
  --arg prd_path "$PRD_PATH" \
  --argjson entries "$entries_json" \
  --argjson git_commits "$git_commits_json" \
  --slurpfile prd "$PRD_PATH" \
  '
  def normalize_result($r):
    if $r == "passed" then "success"
    elif $r == "failed" then "failure"
    else $r
    end;

  def token_reported($entry):
    if ($entry.tokenUsage != null and ($entry.tokenUsage.source // "unavailable") != "unavailable") then true
    elif ($entry.tokenTelemetryAvailable | type) == "boolean" then ($entry.tokenTelemetryAvailable == true)
    else ($entry.tokensUsed != null)
    end;

  def token_source($entry):
    if ($entry.tokenUsage != null) then ($entry.tokenUsage.source // "unavailable")
    elif token_reported($entry) then "legacy_scalar"
    else "unavailable"
    end;

  def input_tokens($entry):
    if ($entry.tokenUsage != null) then ($entry.tokenUsage.input_tokens // 0)
    else 0
    end;

  def output_tokens($entry):
    if ($entry.tokenUsage != null) then ($entry.tokenUsage.output_tokens // 0)
    else 0
    end;

  ($prd[0].issues // []) as $prd_issues
  | ($entries | map(. + {normalized_result: normalize_result(.result // "")})) as $all_entries
  | ($all_entries | map(select(.normalized_result != "requeued_for_feedback"))) as $attempt_entries
  | ($attempt_entries | map(select(.normalized_result == "success")) | length) as $passed_count
  | ($attempt_entries | map(select(.normalized_result == "failure" or .normalized_result == "human_required")) | length) as $failed_count
  | ($attempt_entries | map(select(.normalized_result == "noop" or .normalized_result == "skipped")) | length) as $skipped_count
  | ($all_entries | map(select(.normalized_result == "requeued_for_feedback")) | length) as $feedback_requeues
  | ($attempt_entries | sort_by(.issueId // "") | group_by(.issueId // "")
      | map(select((.[0].issueId // "") != "")
          | (.[0].issueId) as $issue_id
          | ($prd_issues | map(select((.issueId // "") == $issue_id)) | .[0]) as $prd_issue
          | {
              issueId: $issue_id,
              issueTitle: ((.[0].issueTitle // "") // ($prd_issue.title // "")),
              estimatedPoints: (
                (map(.estimatedPoints) | map(select(. != null)) | last)
                // ($prd_issue.estimatedPoints // $prd_issue.estimate // null)
              ),
              priority: ($prd_issue.priority // null),
              attempts: length,
              reportedTokenAttempts: (map(select(token_reported(.))) | length),
              missingTokenAttempts: (map(select(token_reported(.) | not)) | length),
              actualTokens: (map(select(token_reported(.)) | (.tokensUsed // 0)) | add // 0),
              actualInputTokens: (map(select(token_reported(.)) | input_tokens(.)) | add // 0),
              actualOutputTokens: (map(select(token_reported(.)) | output_tokens(.)) | add // 0),
              tokenSources: (map(token_source(.)) | unique),
              actualDurationMs: (map(.durationMs // 0) | add),
              actualFilesChanged: (
                (map(.filesChanged // []) | add | unique | length)
              ),
              finalResult: (.[-1].normalized_result // "unknown")
            }
          | . + {
              tokenTelemetryStatus: (
                if .reportedTokenAttempts == 0 then "missing"
                elif .missingTokenAttempts > 0 then "partial"
                else "reported"
                end
              ),
              tokensPerEstimatedPoint: (
                if (.estimatedPoints != null and .estimatedPoints > 0 and .reportedTokenAttempts > 0)
                then (.actualTokens / .estimatedPoints)
                else null
                end
              ),
              inputOutputRatio: (
                if (.actualOutputTokens > 0)
                then ((.actualInputTokens / .actualOutputTokens) * 100 | round / 100)
                else null
                end
              )
            }
      )) as $estimation_accuracy
  | ($attempt_entries
      | map(select(.normalized_result == "failure" or .normalized_result == "human_required"))
      | map(. + {normalized_failure_category: ((.failureCategory // "") | if . == "" then "unknown" else . end)})
      | sort_by(.normalized_failure_category)
      | group_by(.normalized_failure_category)
      | map({
          category: .[0].normalized_failure_category,
          count: length,
          exampleIssues: (map(.issueId // "") | map(select(length > 0)) | unique | .[0:5])
        })) as $failure_patterns
  | ($estimation_accuracy | map(select((.actualTokens // 0) >= 12000 or (.actualDurationMs // 0) >= 300000))
      | map({issueId: .issueId, issueTitle: .issueTitle, actualTokens: .actualTokens, actualDurationMs: .actualDurationMs})) as $large_scope_issues
  | ($failure_patterns | map(select(.category == "vague-spec" or .category == "missing_context" or .category == "missing-deps"))) as $vague_spec_patterns
  | ($attempt_entries | map(select((.handoffRequired // false) == true)) | length) as $handoff_count
  | ($attempt_entries | map(select((.retryable // false) == true and (.normalized_result == "failure" or .normalized_result == "human_required"))) | length) as $retryable_failure_count
  | ($attempt_entries
      | map(select((.executionIncident // "") == "nested_executor_hang_recovered"))
      | map({
          issueId: (.issueId // null),
          issueTitle: (.issueTitle // ""),
          iteration: (.iteration // null),
          durationMs: (.durationMs // 0),
          summary: (.summary // ""),
          notes: (.incidentNotes // null)
        })) as $nested_executor_hang_entries
  | ($nested_executor_hang_entries | length) as $nested_executor_hang_count
  | ($all_entries | length) as $total_log_entries
  | (
      []
      + (if $feedback_requeues > 0 then [
          {
            severity: "major",
            target: "command spec",
            observation: "Review feedback requeues occurred during run.",
            recommendation: "Tighten pre-merge review criteria and automate feedback ingestion early in each loop."
          }
        ] else [] end)
      + (if ($failure_patterns | length) > 0 then [
          {
            severity: "major",
            target: "agent spec",
            observation: "Failure categories were observed in execution attempts.",
            recommendation: "Prioritize fixes for top failure categories and add targeted guardrail checks."
          }
        ] else [] end)
      + (if $nested_executor_hang_count > 0 then [
          {
            severity: "major",
            target: "executor runtime",
            observation: "One or more nested Codex executors hung and required manual recovery during the run.",
            recommendation: "Add deterministic timeout/heartbeat recovery around nested codex exec and preserve explicit hang incidents in run-log for retrospective analysis."
          }
        ] else [] end)
      + (if ($large_scope_issues | length) > 0 then [
          {
            severity: "minor",
            target: "issue scoping",
            observation: "Some issues exceeded large-scope token/duration thresholds.",
            recommendation: "Split oversized issues into smaller dependency-safe units."
          }
        ] else [] end)
      + (if ($estimation_accuracy | map(select(.tokensPerEstimatedPoint == null)) | length) > 0 then [
          {
            severity: "minor",
            target: "estimation heuristic",
            observation: "Estimated points were missing for one or more issues.",
            recommendation: "Ensure issue generation always emits deterministic estimated points."
          }
        ] else [] end)
    ) as $improvements
  | {
      contract_version: "1.0",
      generatedAt: $generated_at,
      runId: (if $run_id == "" then null else $run_id end),
      source: {
        runLogPath: $run_log_path,
        prdPath: $prd_path
      },
      runSummary: {
        totalLogEntries: $total_log_entries,
        issuesAttempted: ($attempt_entries | length),
        passed: $passed_count,
        failed: $failed_count,
        skipped: $skipped_count,
        feedbackRequeues: $feedback_requeues
      },
      estimationAccuracy: $estimation_accuracy,
      failurePatterns: $failure_patterns,
      scopingObservations: {
        largeScopeIssues: $large_scope_issues,
        vagueSpecPatterns: $vague_spec_patterns,
        missingEstimateCount: ($estimation_accuracy | map(select(.estimatedPoints == null)) | length)
      },
      workflowFriction: {
        feedbackRequeues: $feedback_requeues,
        handoffRequiredCount: $handoff_count,
        retryableFailureCount: $retryable_failure_count,
        nestedExecutorHangCount: $nested_executor_hang_count
      },
      tokenUsageAggregate: {
        totalTokens: ($estimation_accuracy | map(.actualTokens) | add // 0),
        totalInputTokens: ($estimation_accuracy | map(.actualInputTokens // 0) | add // 0),
        totalOutputTokens: ($estimation_accuracy | map(.actualOutputTokens // 0) | add // 0),
        reportedIssueCount: ($estimation_accuracy | map(select(.tokenTelemetryStatus == "reported")) | length),
        partialIssueCount: ($estimation_accuracy | map(select(.tokenTelemetryStatus == "partial")) | length),
        missingIssueCount: ($estimation_accuracy | map(select(.tokenTelemetryStatus == "missing")) | length),
        sources: ($estimation_accuracy | map(.tokenSources // []) | add // [] | unique),
        avgTokensPerIssue: (
          ($estimation_accuracy | map(select(.reportedTokenAttempts > 0))) as $reported
          | if ($reported | length) > 0 then (($reported | map(.actualTokens) | add) / ($reported | length) | round)
            else null
            end
        ),
        avgTokensPerPoint: (
          ($estimation_accuracy | map(select(.tokensPerEstimatedPoint != null))) as $usable
          | if ($usable | length) > 0 then (($usable | map(.tokensPerEstimatedPoint) | add) / ($usable | length) | round)
            else null
            end
        )
      },
      executionIncidents: {
        nestedExecutorHangs: $nested_executor_hang_entries
      },
      proposedImprovements: $improvements,
      gitContext: {
        recentCommits: $git_commits
      }
    }
  ')"

printf '%s\n' "$retrospective_json" > "$OUTPUT_PATH"

jq -n -c \
  --arg output_path "$OUTPUT_PATH" \
  --argjson doc "$retrospective_json" \
  '
  {
    generated: true,
    retrospective_path: $output_path,
    attempted: ($doc.runSummary.issuesAttempted // 0),
    passed: ($doc.runSummary.passed // 0),
    failed: ($doc.runSummary.failed // 0),
    skipped: ($doc.runSummary.skipped // 0),
    improvements_critical: (($doc.proposedImprovements // []) | map(select(.severity == "critical")) | length),
    improvements_major: (($doc.proposedImprovements // []) | map(select(.severity == "major")) | length),
    improvements_minor: (($doc.proposedImprovements // []) | map(select(.severity == "minor")) | length)
  }'
