#!/usr/bin/env bash
#
# Generate an overnight Ralph review context document and checklist from run artifacts.
#

set -euo pipefail

RUN_LOG_PATH=""
RESULTS_DIR=""
PROGRESS_PATH=""
BRANCH=""
OUTPUT_PATH=""
CHECKLIST_OUTPUT_PATH=""
REPO_ROOT="$(pwd)"
TEMPLATE_ROOT=""

usage() {
  cat <<'USAGE'
Usage: scripts/prepare-overnight-review.sh [options]

Options:
  --run-log <path>       Path to run-log.jsonl (required)
  --results-dir <path>   Path to per-issue result JSON directory (required)
  --progress <path>      Path to progress.txt (optional)
  --branch <name>        Branch to diff against merge-base (default: current)
  --output <path>        Output review context markdown path (required)
  --checklist <path>     Output checklist markdown path (default: alongside output)
  --repo-root <path>     Repo root for git operations (default: cwd)
  --template-root <path> Root directory containing templates/ (default: repo-root)
  --help                 Show this help
USAGE
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --run-log) shift; RUN_LOG_PATH="${1:-}" ;;
    --results-dir) shift; RESULTS_DIR="${1:-}" ;;
    --progress) shift; PROGRESS_PATH="${1:-}" ;;
    --branch) shift; BRANCH="${1:-}" ;;
    --output) shift; OUTPUT_PATH="${1:-}" ;;
    --checklist) shift; CHECKLIST_OUTPUT_PATH="${1:-}" ;;
    --repo-root) shift; REPO_ROOT="${1:-}" ;;
    --template-root) shift; TEMPLATE_ROOT="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$RUN_LOG_PATH" ] || [ -z "$RESULTS_DIR" ] || [ -z "$OUTPUT_PATH" ]; then
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

if [ ! -d "$RESULTS_DIR" ]; then
  echo "results directory not found: $RESULTS_DIR" >&2
  exit 1
fi

if [ -z "$TEMPLATE_ROOT" ]; then
  TEMPLATE_ROOT="$REPO_ROOT"
fi

CHECKLIST_TEMPLATE="$TEMPLATE_ROOT/templates/code-review/overnight-ralph-review-checklist.md"

if [ -z "$CHECKLIST_OUTPUT_PATH" ]; then
  CHECKLIST_OUTPUT_PATH="$(dirname "$OUTPUT_PATH")/overnight-ralph-review-checklist.md"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")" "$(dirname "$CHECKLIST_OUTPUT_PATH")"

if [ -z "$BRANCH" ]; then
  BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
fi

# ---------------------------------------------------------------------------
# Parse run-log entries
# ---------------------------------------------------------------------------

run_log_json="$(jq -Rsc '
  split("\n")
  | map(select(length > 0))
  | map(fromjson? // {"_invalid": true})
  | map(select(type == "object" and (._invalid // false) != true))
' "$RUN_LOG_PATH")"

# ---------------------------------------------------------------------------
# Collect per-issue result JSONs
# ---------------------------------------------------------------------------

result_files_json="[]"
if compgen -G "$RESULTS_DIR"/*-result.json >/dev/null 2>&1; then
  result_files_json="$(
    for f in "$RESULTS_DIR"/*-result.json; do
      jq -c '. + {"_result_path": "'"$f"'"}' "$f" 2>/dev/null || true
    done | jq -sc '.'
  )"
fi

# ---------------------------------------------------------------------------
# Parse progress.txt run window
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Git merge-base diff for changed files
# ---------------------------------------------------------------------------

git_changed_files_json='[]'
merge_base=""
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  default_branch="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")"
  merge_base="$(git -C "$REPO_ROOT" merge-base "$default_branch" HEAD 2>/dev/null || echo "")"
  if [ -n "$merge_base" ]; then
    git_changed_files_json="$(git -C "$REPO_ROOT" diff --name-only "$merge_base"..HEAD 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')"
  fi
fi

# ---------------------------------------------------------------------------
# Build the sidecar JSON with all synthesis
# ---------------------------------------------------------------------------

generated_at="$(now_iso)"

sidecar_json="$(jq -n -c \
  --arg generated_at "$generated_at" \
  --arg branch "$BRANCH" \
  --arg run_log_path "$RUN_LOG_PATH" \
  --arg results_dir "$RESULTS_DIR" \
  --arg progress_path "$PROGRESS_PATH" \
  --arg merge_base "$merge_base" \
  --arg window_start "$window_start" \
  --arg window_end "$window_end" \
  --argjson run_log "$run_log_json" \
  --argjson result_files "$result_files_json" \
  --argjson git_changed_files "$git_changed_files_json" \
  '
  def normalize_result($r):
    if $r == "passed" then "success"
    elif $r == "failed" then "failure"
    else $r
    end;

  def severity_rank:
    if . == "failure" then 1
    elif . == "human_required" then 2
    elif . == "success" then 3
    elif . == "noop" or . == "skipped" then 4
    else 5
    end;

  # Normalized run-log entries
  ($run_log | map(. + {
    norm_result: normalize_result(.result // .outcome // ""),
    norm_issue_id: (.issueId // .issue_id // "")
  })) as $entries

  | ($entries | map(select(.norm_result != "requeued_for_feedback"))) as $attempt_entries

  | ($attempt_entries | map(select(.norm_result == "success")) | length) as $success_count
  | ($attempt_entries | map(select(.norm_result == "failure")) | length) as $failure_count
  | ($attempt_entries | map(select(.norm_result == "human_required")) | length) as $human_required_count
  | ($attempt_entries | map(select((.retryable // false) == true and .norm_result == "failure")) | length) as $retryable_count

  # Build per-issue ledger from result files merged with run-log data
  | ($result_files
      | map(
          (.issue_id // .issueId // "") as $rid
          | ($attempt_entries | map(select(.norm_issue_id == $rid)) | last) as $log_entry
          | {
              issue_id: $rid,
              issue_title: (.issueTitle // .issue_title // ($log_entry.issueTitle // "")),
              outcome: normalize_result(.outcome // ($log_entry.result // "")),
              failure_category: (.failure_category // .failureCategory // ($log_entry.failureCategory // null)),
              retryable: (.retryable // ($log_entry.retryable // false)),
              handoff_required: (.handoff_required // .handoffRequired // ($log_entry.handoffRequired // false)),
              summary: (.summary // ($log_entry.summary // "")),
              result_path: (._result_path // ""),
              iteration: (.iteration // ($log_entry.iteration // null)),
              duration_ms: ((.metrics.duration_ms // .duration_ms // ($log_entry.durationMs // 0))),
              validation: (.validation_results // ($log_entry.validationResults // {})),
              files_changed: ((.artifacts.files_changed // .filesChanged // ($log_entry.filesChanged // [])) | map(select(type == "string" and length > 0))),
              timestamp: ($log_entry.timestamp // null)
            }
        )
      | map(select(.issue_id != ""))
    ) as $issue_ledger

  # Sort by severity for triage
  | ($issue_ledger
      | sort_by(.outcome | severity_rank)
    ) as $sorted_ledger

  # Aggregate changed areas from result artifacts
  | ($issue_ledger
      | map(.files_changed)
      | add // []
      | unique
    ) as $artifact_changed_files

  # Combine git diff files + artifact files
  | (($git_changed_files + $artifact_changed_files) | unique) as $all_changed_files

  # Categorize files by area
  | ($all_changed_files
      | map(
          (split("/")[0:2] | join("/")) as $prefix
          | {file: ., area: (
              if startswith("contracts/") then "contracts"
              elif startswith("scripts/") then "scripts"
              elif startswith("commands/") then "commands"
              elif startswith("templates/") then "templates"
              elif startswith("skills/") then "skills"
              elif startswith("rules/") then "rules"
              elif startswith(".cursor/") then "config"
              elif startswith(".ralph/") then "ralph-artifacts"
              elif (endswith(".test.sh") or endswith(".test.ts") or endswith(".test.js") or startswith("test") or contains("/test")) then "tests"
              else "other"
              end),
            prefix: $prefix
          }
        )
    ) as $categorized_files

  | ($categorized_files
      | group_by(.area)
      | map({area: .[0].area, count: length, files: [.[].file]})
      | sort_by(.count * -1)
    ) as $area_summary

  # High-risk flags
  | ($all_changed_files | map(select(
      startswith("contracts/")
      or startswith("rules/")
      or startswith(".cursor/rules/")
      or endswith(".env")
      or endswith(".env.example")
      or contains("secret")
      or contains("auth")
      or contains("security")
      or endswith(".json") and (startswith("package") or startswith("tsconfig"))
    ))) as $high_risk_files

  | ($categorized_files
      | group_by(.prefix)
      | map({prefix: .[0].prefix, count: length})
      | sort_by(.count * -1)
    ) as $prefix_heatmap

  | {
      generated_at: $generated_at,
      branch: $branch,
      merge_base: (if $merge_base == "" then null else $merge_base end),
      run_window: {
        start: (if $window_start == "" then null else $window_start end),
        end: (if $window_end == "" then null else $window_end end)
      },
      source: {
        run_log_path: $run_log_path,
        results_dir: $results_dir,
        progress_path: (if $progress_path == "" then null else $progress_path end)
      },
      outcome_snapshot: {
        issues_attempted: ($attempt_entries | length),
        success: $success_count,
        failure: $failure_count,
        human_required: $human_required_count,
        retryable_failures: $retryable_count
      },
      triage_queue: $sorted_ledger,
      validation_matrix: ($issue_ledger | map({
        issue_id: .issue_id,
        lint: (.validation.lint // "n/a"),
        typecheck: (.validation.typecheck // "n/a"),
        test: (.validation.test // "n/a"),
        build: (.validation.build // "n/a")
      })),
      changed_files_total: ($all_changed_files | length),
      area_summary: $area_summary,
      prefix_heatmap: $prefix_heatmap,
      high_risk_files: $high_risk_files,
      high_risk_count: ($high_risk_files | length)
    }
')"

# ---------------------------------------------------------------------------
# Emit review context markdown
# ---------------------------------------------------------------------------

{
  echo "# Overnight Ralph Review Context"
  echo
  echo "## Run Artifacts"
  echo
  printf -- '- Branch: `%s`\n' "$(jq -r '.branch' <<< "$sidecar_json")"
  printf -- '- Merge base: `%s`\n' "$(jq -r '.merge_base // "n/a"' <<< "$sidecar_json")"
  printf -- '- Progress log: `%s`\n' "$(jq -r '.source.progress_path // "n/a"' <<< "$sidecar_json")"
  printf -- '- Run log: `%s`\n' "$(jq -r '.source.run_log_path' <<< "$sidecar_json")"
  printf -- '- Result directory: `%s`\n' "$(jq -r '.source.results_dir' <<< "$sidecar_json")"
  printf -- '- Generated at: `%s`\n' "$(jq -r '.generated_at' <<< "$sidecar_json")"
  run_win_start="$(jq -r '.run_window.start // "n/a"' <<< "$sidecar_json")"
  run_win_end="$(jq -r '.run_window.end // "n/a"' <<< "$sidecar_json")"
  printf -- '- Run window: `%s` -> `%s`\n' "$run_win_start" "$run_win_end"

  echo
  echo "## Outcome Snapshot"
  echo
  echo "| Metric | Value |"
  echo "| --- | --- |"
  echo "| Issues attempted | $(jq -r '.outcome_snapshot.issues_attempted' <<< "$sidecar_json") |"
  echo "| Success | $(jq -r '.outcome_snapshot.success' <<< "$sidecar_json") |"
  echo "| Failure | $(jq -r '.outcome_snapshot.failure' <<< "$sidecar_json") |"
  echo "| Human required | $(jq -r '.outcome_snapshot.human_required' <<< "$sidecar_json") |"
  echo "| Retryable failures | $(jq -r '.outcome_snapshot.retryable_failures' <<< "$sidecar_json") |"

  echo
  echo "## First-Pass Triage Queue"
  echo
  echo "Review this queue in order."

  triage_count="$(jq -r '.triage_queue | length' <<< "$sidecar_json")"
  if [ "$triage_count" = "0" ]; then
    echo
    echo "- No issues found in result artifacts."
  else
    idx=1
    while IFS= read -r issue_json; do
      issue_id="$(jq -r '.issue_id' <<< "$issue_json")"
      issue_title="$(jq -r '.issue_title' <<< "$issue_json")"
      outcome="$(jq -r '.outcome' <<< "$issue_json")"
      failure_cat="$(jq -r '.failure_category // "none"' <<< "$issue_json")"
      retryable="$(jq -r '.retryable' <<< "$issue_json")"
      summary="$(jq -r '.summary' <<< "$issue_json")"
      result_path="$(jq -r '.result_path' <<< "$issue_json")"
      timestamp="$(jq -r '.timestamp // "n/a"' <<< "$issue_json")"

      echo
      echo "### ${idx}. \`${issue_id}\` - ${issue_title}"
      echo
      printf -- '- Outcome: `%s`\n' "$outcome"
      printf -- '- Failure category: `%s`\n' "$failure_cat"
      printf -- '- Retryable: `%s`\n' "$retryable"
      printf -- '- Summary: %s\n' "$summary"
      printf -- '- Result artifact: `%s`\n' "$result_path"
      printf -- '- Run-log timestamp: `%s`\n' "$timestamp"

      changed_areas="$(jq -r '.files_changed | map(split("/")[0:2] | join("/")) | unique | .[]' <<< "$issue_json" 2>/dev/null || true)"
      if [ -n "$changed_areas" ]; then
        echo "- Changed areas:"
        while IFS= read -r area; do
          printf '  - `%s`\n' "$area"
        done <<< "$changed_areas"
      fi

      changed_files="$(jq -r '.files_changed[]' <<< "$issue_json" 2>/dev/null || true)"
      if [ -n "$changed_files" ]; then
        echo "- Changed files:"
        while IFS= read -r fpath; do
          printf '  - `%s`\n' "$fpath"
        done <<< "$changed_files"
      fi

      idx=$((idx + 1))
    done < <(jq -c '.triage_queue[]' <<< "$sidecar_json")
  fi

  echo
  echo "## Validation Signals"
  echo
  validation_count="$(jq -r '.validation_matrix | length' <<< "$sidecar_json")"
  if [ "$validation_count" = "0" ]; then
    echo "- No validation data available."
  else
    echo "| Issue | lint | typecheck | test | build |"
    echo "| --- | --- | --- | --- | --- |"
    jq -r '.validation_matrix[] | "| `\(.issue_id)` | `\(.lint)` | `\(.typecheck)` | `\(.test)` | `\(.build)` |"' <<< "$sidecar_json"
  fi

  echo
  echo "## Changed Area Heatmap"
  echo
  area_count="$(jq -r '.area_summary | length' <<< "$sidecar_json")"
  if [ "$area_count" = "0" ]; then
    echo "- No changed files detected."
  else
    echo "| Area | Files Changed |"
    echo "| --- | --- |"
    jq -r '.area_summary[] | "| `\(.area)` | \(.count) |"' <<< "$sidecar_json"

    echo
    echo "### Prefix Breakdown"
    echo
    echo "| Prefix | Files |"
    echo "| --- | --- |"
    jq -r '.prefix_heatmap[] | "| `\(.prefix)` | \(.count) |"' <<< "$sidecar_json"
  fi

  high_risk_count="$(jq -r '.high_risk_count' <<< "$sidecar_json")"
  if [ "$high_risk_count" != "0" ]; then
    echo
    echo "## High-Risk Changes"
    echo
    echo "These files are in security-sensitive, contract, or config paths:"
    echo
    jq -r '.high_risk_files[] | "- `\(.)`"' <<< "$sidecar_json"
  fi

  echo
  echo "## Notes For Morning Reviewer"
  echo
  echo "- Start with failures/handoffs before successful issues."
  echo "- Confirm rollback options for any risky file groups."
  echo "- Record follow-up issue IDs for anything deferred."
} > "$OUTPUT_PATH"

# ---------------------------------------------------------------------------
# Copy or generate checklist
# ---------------------------------------------------------------------------

if [ -f "$CHECKLIST_TEMPLATE" ]; then
  cp "$CHECKLIST_TEMPLATE" "$CHECKLIST_OUTPUT_PATH"
else
  cat > "$CHECKLIST_OUTPUT_PATH" <<'CHECKLIST'
# Overnight Ralph Review Checklist

## Correctness

- [ ] Acceptance criteria in each executed issue still match the implemented behavior.
- [ ] No cross-issue regressions are introduced by overlapping file changes.
- [ ] Failure summaries in result JSON match observed repository state.

## Test Coverage

- [ ] Required validations (`lint`, `typecheck`, `test`, `build`) are pass/skipped with explicit rationale.
- [ ] New or changed behavior has deterministic test coverage or an explicit follow-up issue.
- [ ] Any skipped checks are triaged with owner and due date.

## Rollback Safety

- [ ] High-risk changes have a clear rollback or revert path.
- [ ] Breaking config/contract changes are identified before merge.
- [ ] Rollback instructions are documented for operationally sensitive updates.

## Security

- [ ] Auth, secret handling, and permission boundaries were not weakened.
- [ ] New scripts/automation avoid unsafe command execution patterns.
- [ ] Security-sensitive deltas are reviewed first in the triage queue.

## Docs Drift

- [ ] Commands/contracts/docs changed by Ralph stay aligned.
- [ ] User-facing command references match current file paths and names.
- [ ] Any required follow-up documentation updates are explicitly tracked.

## Decision Log

- [ ] Triage decision recorded for every non-success outcome.
- [ ] Owners assigned for follow-up actions and retry/handoff work.
- [ ] Final review disposition documented (`approve`, `needs changes`, or `hold`).
CHECKLIST
fi

# ---------------------------------------------------------------------------
# Summary JSON to stdout
# ---------------------------------------------------------------------------

jq -n -c \
  --arg output "$OUTPUT_PATH" \
  --arg checklist "$CHECKLIST_OUTPUT_PATH" \
  --argjson doc "$sidecar_json" \
  '{
    generated: true,
    context_path: $output,
    checklist_path: $checklist,
    issues_attempted: ($doc.outcome_snapshot.issues_attempted // 0),
    success: ($doc.outcome_snapshot.success // 0),
    failure: ($doc.outcome_snapshot.failure // 0),
    human_required: ($doc.outcome_snapshot.human_required // 0),
    changed_files_total: ($doc.changed_files_total // 0),
    high_risk_count: ($doc.high_risk_count // 0),
    triage_queue_count: (($doc.triage_queue // []) | length)
  }'
