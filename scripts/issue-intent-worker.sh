#!/usr/bin/env bash
#
# Process queued issue-creation intents and append deterministic result records.
#

set -euo pipefail

QUEUE_PATH=""
RESULTS_PATH=""
CREATOR_CMD="scripts/mock-linear-issue-creator.sh"
MAX_INTENTS=100

usage() {
  cat <<'EOF'
Usage: scripts/issue-intent-worker.sh [options]

Options:
  --queue <path>        Intent queue JSONL path (required)
  --results <path>      Result JSONL path (required)
  --creator-cmd <cmd>   Issue creator command (default: scripts/mock-linear-issue-creator.sh)
  --max <number>        Max intents to process per run (default: 100)
  --help                Show this help
EOF
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --queue) shift; QUEUE_PATH="${1:-}" ;;
    --results) shift; RESULTS_PATH="${1:-}" ;;
    --creator-cmd) shift; CREATOR_CMD="${1:-}" ;;
    --max) shift; MAX_INTENTS="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$QUEUE_PATH" ] || [ -z "$RESULTS_PATH" ]; then
  usage >&2
  exit 1
fi

if ! [[ "$MAX_INTENTS" =~ ^[0-9]+$ ]] || [ "$MAX_INTENTS" -lt 1 ]; then
  echo "--max must be an integer >= 1" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$QUEUE_PATH")" "$(dirname "$RESULTS_PATH")"
touch "$QUEUE_PATH" "$RESULTS_PATH"

read -r -a CREATOR_CMD_ARR <<< "$CREATOR_CMD"
if [ "${#CREATOR_CMD_ARR[@]}" -eq 0 ]; then
  echo "invalid --creator-cmd value" >&2
  exit 1
fi
if ! command -v "${CREATOR_CMD_ARR[0]}" >/dev/null 2>&1; then
  echo "creator command not found: ${CREATOR_CMD_ARR[0]}" >&2
  exit 1
fi

processed=0
created=0
failed=0
skipped=0
created_issue_ids='[]'

while IFS= read -r intent_line; do
  [ -z "$intent_line" ] && continue
  [ "$processed" -ge "$MAX_INTENTS" ] && break

  status="$(jq -r '.status // "pending"' <<< "$intent_line")"
  [ "$status" != "pending" ] && continue

  intent_id="$(jq -r '.intent_id // ""' <<< "$intent_line")"
  dedup_key="$(jq -r '.dedup_key // ""' <<< "$intent_line")"
  [ -z "$dedup_key" ] && continue

  processed=$((processed + 1))

  exists="$(jq -s --arg key "$dedup_key" '
    [ .[] | select(.dedup_key == $key and ((.outcome // "") == "created" or (.outcome // "") == "skipped_duplicate")) ] | length
  ' "$RESULTS_PATH")"
  if [ "$exists" -gt 0 ]; then
    skipped=$((skipped + 1))
    continue
  fi

  intent_file="$(mktemp)"
  output_file="$(mktemp)"
  printf '%s\n' "$intent_line" > "$intent_file"

  set +e
  "${CREATOR_CMD_ARR[@]}" --intent-json "$intent_file" --output-json "$output_file"
  rc=$?
  set -e

  timestamp="$(now_iso)"

  if [ "$rc" -eq 0 ] && [ -f "$output_file" ] && jq -e '.' "$output_file" >/dev/null 2>&1; then
    issue_id="$(jq -r '.issue_id // .issueId // .identifier // .id // ""' "$output_file")"
    issue_url="$(jq -r '.url // .issue_url // ""' "$output_file")"
    if [ -n "$issue_id" ]; then
      created=$((created + 1))
      created_issue_ids="$(jq -c --arg id "$issue_id" '
        if index($id) == null then . + [$id] else . end
      ' <<< "$created_issue_ids")"

      jq -n -c \
        --arg timestamp "$timestamp" \
        --arg intent_id "$intent_id" \
        --arg dedup_key "$dedup_key" \
        --arg issue_id "$issue_id" \
        --arg issue_url "$issue_url" \
        '
        {
          timestamp: $timestamp,
          intent_id: $intent_id,
          dedup_key: $dedup_key,
          outcome: "created",
          issue_id: $issue_id,
          issue_url: (if $issue_url == "" then null else $issue_url end)
        }' >> "$RESULTS_PATH"
    else
      failed=$((failed + 1))
      jq -n -c \
        --arg timestamp "$timestamp" \
        --arg intent_id "$intent_id" \
        --arg dedup_key "$dedup_key" \
        '
        {
          timestamp: $timestamp,
          intent_id: $intent_id,
          dedup_key: $dedup_key,
          outcome: "failed",
          error: "creator returned no issue identifier"
        }' >> "$RESULTS_PATH"
    fi
  else
    failed=$((failed + 1))
    jq -n -c \
      --arg timestamp "$timestamp" \
      --arg intent_id "$intent_id" \
      --arg dedup_key "$dedup_key" \
      --argjson exit_code "$rc" \
      '
      {
        timestamp: $timestamp,
        intent_id: $intent_id,
        dedup_key: $dedup_key,
        outcome: "failed",
        error: ("creator command failed with exit code " + ($exit_code | tostring))
      }' >> "$RESULTS_PATH"
  fi

  rm -f "$intent_file" "$output_file"
done < "$QUEUE_PATH"

jq -n -c \
  --argjson processed "$processed" \
  --argjson created "$created" \
  --argjson failed "$failed" \
  --argjson skipped "$skipped" \
  --argjson created_issue_ids "$created_issue_ids" \
  '
  {
    processed: $processed,
    created: $created,
    failed: $failed,
    skipped: $skipped,
    created_issue_ids: $created_issue_ids
  }'
