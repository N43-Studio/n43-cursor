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

  has_supersedes_issue_id="$(jq -r '
    ((.payload // {}) | has("supersedes_issue_id")) and (((.payload.supersedes_issue_id // "") | length) > 0)
  ' <<< "$intent_line")"
  if [ "$has_supersedes_issue_id" = "true" ]; then
    guardrails_valid="$(jq -r '
      (.payload.decomposition_guardrails // null) as $g
      | ($g != null)
      and (($g.require_children_runnable_before_parent_terminalization // false) == true)
      and (($g.forbid_sub_issue_link_to_superseded_parent // false) == true)
      and (($g.allowed_replacement_link_types // []) | type == "array")
      and (($g.allowed_replacement_link_types // []) | index("related") != null)
      and (($g.allowed_replacement_link_types // []) | index("blockedBy") != null)
      and (($g.allowed_replacement_link_types // []) | index("blocks") != null)
      and (($g.preferred_parent_terminal_state // "") == "done")
    ' <<< "$intent_line")"
    if [ "$guardrails_valid" != "true" ]; then
      failed=$((failed + 1))
      timestamp="$(now_iso)"
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
          error: "replacement-child intent missing required decomposition guardrails"
        }' >> "$RESULTS_PATH"
      continue
    fi
  fi

  intent_parent_id="$(jq -r '.payload.parentId // .parentId // ""' <<< "$intent_line")"
  if [ -n "$intent_parent_id" ]; then
    echo "[cascade-safety] intent ${intent_id} creates a child of ${intent_parent_id} — if the parent is later canceled, this child will be auto-canceled by Linear. Unparent before canceling. See contracts/ralph/core/issue-decomposition-safety.md" >&2
  fi

  intent_description="$(jq -r '.payload.description // .description // ""' <<< "$intent_line")"

  if [ -n "$intent_parent_id" ] && [ -n "$intent_description" ] && ! printf '%s' "$intent_description" | grep -q 'cascade cancellation'; then
    cascade_note=$'\n\n> **Cascade Safety**: This issue is a child of '"${intent_parent_id}"'. If the parent issue needs to be closed, unparent this issue first (set parentId to null) to prevent cascade cancellation. See `contracts/ralph/core/issue-decomposition-safety.md`.'
    intent_line="$(jq -c --arg note "$cascade_note" '
      if .payload.description then
        .payload.description += $note
      elif .description then
        .description += $note
      else . end
    ' <<< "$intent_line")"
    intent_description="$(jq -r '.payload.description // .description // ""' <<< "$intent_line")"
  fi

  if [ -n "$intent_description" ] && ! printf '%s' "$intent_description" | grep -q '## Metadata Rationale'; then
    default_metadata_section=$(cat <<'MDSECTION'

## Metadata Rationale
- `priority=3 (Medium)`: default — insufficient context for deterministic scoring
- `estimate=2`: default — assumed moderate scope
- `estimatedTokens=6400`: default — moderate implementation estimate
- `confidence=0.50`: default — metadata was injected by intent worker
- `lowConfidence=true`: metadata rationale was missing from source; review recommended
- `rubricFactors={}`

- intent worker injected default metadata rationale (source did not include one)
MDSECTION
)
    intent_line="$(jq -c --arg section "$default_metadata_section" '
      if .payload.description then
        .payload.description += $section
      elif .description then
        .description += $section
      else . end
    ' <<< "$intent_line")"
  fi

  intent_labels="$(jq -r '(.payload.labels // .labels // "") | if type == "array" then join(",") else . end' <<< "$intent_line")"
  missing_labels=""
  for required_label in "Ralph" "Agent Generated"; do
    if ! printf '%s' "$intent_labels" | grep -q "$required_label"; then
      missing_labels="${missing_labels:+${missing_labels},}${required_label}"
    fi
  done
  if [ -n "$missing_labels" ]; then
    if [ -n "$intent_labels" ]; then
      new_labels="${intent_labels},${missing_labels}"
    else
      new_labels="$missing_labels"
    fi
    intent_line="$(jq -c --arg labels "$new_labels" '
      if .payload.labels then
        .payload.labels = ($labels | split(","))
      elif .labels then
        .labels = ($labels | split(","))
      else . end
    ' <<< "$intent_line")"
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
