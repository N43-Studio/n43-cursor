#!/usr/bin/env bash
#
# Process reviewed-state feedback events and return deterministic requeue decisions.
#

set -euo pipefail

EVENTS_PATH=""
STATE_PATH=""
STATUSES_CSV="Reviewed,Needs Review"
RUN_ID=""
WINDOW_START=""
WINDOW_END=""

usage() {
  cat <<'USAGE'
Usage: scripts/review-feedback-sweep.sh [options]

Options:
  --events <path>      Feedback events JSONL path (required)
  --state <path>       Sweep cursor/state JSON path (required)
  --statuses <csv>     Status values to consider (default: Reviewed,Needs Review)
  --run-id <id>        Run identifier for trace output (optional)
  --window-start <iso> Run window start timestamp (optional)
  --window-end <iso>   Run window end timestamp (optional)
  --help               Show this help
USAGE
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --events) shift; EVENTS_PATH="${1:-}" ;;
    --state) shift; STATE_PATH="${1:-}" ;;
    --statuses) shift; STATUSES_CSV="${1:-}" ;;
    --run-id) shift; RUN_ID="${1:-}" ;;
    --window-start) shift; WINDOW_START="${1:-}" ;;
    --window-end) shift; WINDOW_END="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$EVENTS_PATH" ] || [ -z "$STATE_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$EVENTS_PATH")" "$(dirname "$STATE_PATH")"
touch "$EVENTS_PATH"

if [ ! -f "$STATE_PATH" ]; then
  jq -n '{last_index: 0, updated_at: null}' > "$STATE_PATH"
fi

last_index="$(jq -r '.last_index // 0' "$STATE_PATH" 2>/dev/null || echo 0)"
if ! [[ "$last_index" =~ ^[0-9]+$ ]]; then
  last_index=0
fi

statuses_json="$(jq -n -c --arg csv "$STATUSES_CSV" '
  $csv
  | split(",")
  | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
  | map(select(length > 0))
')"

events_json="$(jq -Rsc '
  split("\n")
  | map(select(length > 0))
  | map(fromjson? // {"_invalid": true})
' "$EVENTS_PATH")"

summary_json="$(jq -n -c \
  --argjson entries "$events_json" \
  --argjson start "$last_index" \
  --argjson statuses "$statuses_json" \
  --arg run_id "$RUN_ID" \
  --arg window_start "$WINDOW_START" \
  --arg window_end "$WINDOW_END" \
  '
  ($entries | length) as $total
  | ($entries[$start:] // []) as $delta
  | ($delta | map(select(type == "object" and (._invalid // false) == true)) | length) as $invalid_count
  | ($delta | map(select(type == "object" and (._invalid // false) != true))) as $valid_entries
  | ($valid_entries | map(
      (.source_status // .status // .current_status // "") as $status
      | . + {__status: $status}
    )) as $status_augmented
  | ($status_augmented | map(select((.__status as $status | ($statuses | index($status)) != null)))) as $status_matches
  | ($status_matches | map(
      select(
        (.requires_rework // false) == true
        or ((.feedback_type // .action // .review_decision // "") | IN("requeue", "reopen", "changes_requested", "revision_requested", "needs_changes"))
      )
      | (.issue_id // .issueId // .identifier // "")
      | select(length > 0)
    ) | unique) as $requeue_ids
  | {
      processed_events: ($delta | length),
      matched_status_events: ($status_matches | length),
      ignored_events: (($valid_entries | length) - ($status_matches | length)),
      invalid_events: $invalid_count,
      requeue_issue_ids: $requeue_ids,
      previous_index: $start,
      next_index: $total,
      statuses: $statuses,
      run_id: (if $run_id == "" then null else $run_id end),
      window_start: (if $window_start == "" then null else $window_start end),
      window_end: (if $window_end == "" then null else $window_end end)
    }
  ')"

next_index="$(jq -r '.next_index // 0' <<< "$summary_json")"
if ! [[ "$next_index" =~ ^[0-9]+$ ]]; then
  next_index="$last_index"
fi

jq -n \
  --argjson last_index "$next_index" \
  --arg updated_at "$(now_iso)" \
  '{last_index: $last_index, updated_at: $updated_at}' > "$STATE_PATH"

printf '%s\n' "$summary_json"
