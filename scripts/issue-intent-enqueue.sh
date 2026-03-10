#!/usr/bin/env bash
#
# Enqueue deterministic Linear issue-creation intents for delegated processing.
#

set -euo pipefail

QUEUE_PATH=""
RESULTS_PATH=""
DEDUP_KEY=""
TITLE=""
DESCRIPTION=""
TEAM="Studio"
PROJECT=""
PRIORITY=""
LABELS_CSV=""

usage() {
  cat <<'EOF'
Usage: scripts/issue-intent-enqueue.sh [options]

Options:
  --queue <path>        Intent queue JSONL path (required)
  --results <path>      Result JSONL path (required)
  --dedup-key <key>     Deterministic dedup/idempotency key (required)
  --title <text>        Issue title (required)
  --description <text>  Issue description (optional)
  --team <name>         Linear team key/name (default: Studio)
  --project <name>      Linear project identifier (optional)
  --priority <num>      Linear priority value (optional)
  --labels <csv>        Comma-separated labels (optional)
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
    --dedup-key) shift; DEDUP_KEY="${1:-}" ;;
    --title) shift; TITLE="${1:-}" ;;
    --description) shift; DESCRIPTION="${1:-}" ;;
    --team) shift; TEAM="${1:-}" ;;
    --project) shift; PROJECT="${1:-}" ;;
    --priority) shift; PRIORITY="${1:-}" ;;
    --labels) shift; LABELS_CSV="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$QUEUE_PATH" ] || [ -z "$RESULTS_PATH" ] || [ -z "$DEDUP_KEY" ] || [ -z "$TITLE" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$QUEUE_PATH")" "$(dirname "$RESULTS_PATH")"
touch "$QUEUE_PATH" "$RESULTS_PATH"

pending_exists="$(jq -s --arg key "$DEDUP_KEY" '
  [ .[] | select(.dedup_key == $key and (.status // "pending") == "pending") ] | length
' "$QUEUE_PATH")"

result_exists="$(jq -s --arg key "$DEDUP_KEY" '
  [ .[] | select(.dedup_key == $key and ((.outcome // "") == "created" or (.outcome // "") == "skipped_duplicate")) ] | length
' "$RESULTS_PATH")"

if [ "$pending_exists" -gt 0 ] || [ "$result_exists" -gt 0 ]; then
  jq -n -c --arg dedup_key "$DEDUP_KEY" '
    {
      status: "skipped_duplicate",
      dedup_key: $dedup_key
    }'
  exit 0
fi

labels_json="$(jq -n -c --arg csv "$LABELS_CSV" '
  if ($csv | length) == 0 then
    []
  else
    ($csv
      | split(",")
      | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
      | map(select(length > 0))
    )
  end
')"

priority_json="null"
if [ -n "$PRIORITY" ]; then
  priority_json="$PRIORITY"
fi

intent_id="intent-$(date -u +%Y%m%dT%H%M%SZ)-$$"
created_at="$(now_iso)"

jq -n -c \
  --arg intent_id "$intent_id" \
  --arg dedup_key "$DEDUP_KEY" \
  --arg created_at "$created_at" \
  --arg title "$TITLE" \
  --arg description "$DESCRIPTION" \
  --arg team "$TEAM" \
  --arg project "$PROJECT" \
  --argjson priority "$priority_json" \
  --argjson labels "$labels_json" \
  '
  {
    intent_id: $intent_id,
    dedup_key: $dedup_key,
    created_at: $created_at,
    status: "pending",
    payload: {
      title: $title,
      description: $description,
      team: $team,
      project: (if $project == "" then null else $project end),
      priority: $priority,
      labels: $labels
    }
  }' >> "$QUEUE_PATH"

jq -n -c --arg intent_id "$intent_id" --arg dedup_key "$DEDUP_KEY" '
  {
    status: "enqueued",
    intent_id: $intent_id,
    dedup_key: $dedup_key
  }'
