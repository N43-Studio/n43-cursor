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
ESTIMATE=""
LABELS_CSV=""
SUPERSEDES_ISSUE_ID=""

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
  --estimate <num>      Linear estimate value (optional)
  --labels <csv>        Comma-separated labels (optional)
  --supersedes-issue <id>
                         Superseded umbrella Issue identifier for decomposition safety guardrails (optional)
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
    --estimate) shift; ESTIMATE="${1:-}" ;;
    --labels) shift; LABELS_CSV="${1:-}" ;;
    --supersedes-issue) shift; SUPERSEDES_ISSUE_ID="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$QUEUE_PATH" ] || [ -z "$RESULTS_PATH" ] || [ -z "$DEDUP_KEY" ] || [ -z "$TITLE" ]; then
  usage >&2
  exit 1
fi

if [ -n "$SUPERSEDES_ISSUE_ID" ] && ! [[ "$SUPERSEDES_ISSUE_ID" =~ ^[A-Za-z0-9]+-[0-9]+$ ]]; then
  echo "--supersedes-issue must look like a Linear Issue identifier (for example N43-481)" >&2
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
  if ! [[ "$PRIORITY" =~ ^[0-9]+$ ]]; then
    echo "--priority must be an integer when provided" >&2
    exit 1
  fi
  priority_json="$PRIORITY"
fi

estimate_json="null"
if [ -n "$ESTIMATE" ]; then
  if ! [[ "$ESTIMATE" =~ ^[0-9]+$ ]]; then
    echo "--estimate must be an integer when provided" >&2
    exit 1
  fi
  estimate_json="$ESTIMATE"
fi

decomposition_guardrails_json="null"
if [ -n "$SUPERSEDES_ISSUE_ID" ]; then
  decomposition_guardrails_json='{
    "require_children_runnable_before_parent_terminalization": true,
    "forbid_sub_issue_link_to_superseded_parent": true,
    "allowed_replacement_link_types": ["related", "blockedBy", "blocks"],
    "preferred_parent_terminal_state": "done"
  }'
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
  --arg supersedes_issue_id "$SUPERSEDES_ISSUE_ID" \
  --argjson priority "$priority_json" \
  --argjson estimate "$estimate_json" \
  --argjson labels "$labels_json" \
  --argjson decomposition_guardrails "$decomposition_guardrails_json" \
  '
  {
    intent_id: $intent_id,
    dedup_key: $dedup_key,
    created_at: $created_at,
    status: "pending",
    payload: (
      {
        title: $title,
        description: $description,
        team: $team,
        project: (if $project == "" then null else $project end),
        priority: $priority,
        estimate: $estimate,
        labels: $labels
      }
      | if $supersedes_issue_id != "" then
          . + {
            supersedes_issue_id: $supersedes_issue_id,
            decomposition_guardrails: $decomposition_guardrails
          }
        else
          .
        end
    )
  }' >> "$QUEUE_PATH"

jq -n -c --arg intent_id "$intent_id" --arg dedup_key "$DEDUP_KEY" '
  {
    status: "enqueued",
    intent_id: $intent_id,
    dedup_key: $dedup_key
  }'
