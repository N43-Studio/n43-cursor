#!/usr/bin/env bash
#
# Convert retrospective proposed improvements into delegated issue-creation intents.
#

set -euo pipefail

RETROSPECTIVE_PATH=""
QUEUE_PATH=""
RESULTS_PATH=""
ENQUEUE_CMD="scripts/issue-intent-enqueue.sh"
TEAM="Studio"
PROJECT=""
LABELS_BASE_CSV="Ralph,Improvement"

usage() {
  cat <<'USAGE'
Usage: scripts/retrospective-to-issue-intents.sh [options]

Options:
  --retrospective <path>  Retrospective JSON path (required)
  --queue <path>          Intent queue JSONL path (required)
  --results <path>        Intent result JSONL path (required)
  --enqueue-cmd <cmd>     Intent enqueue command (default: scripts/issue-intent-enqueue.sh)
  --team <name>           Linear team key/name (default: Studio)
  --project <name>        Linear project identifier/name (optional)
  --labels-base <csv>     Base labels CSV (default: Ralph,Improvement)
  --help                  Show this help
USAGE
}

hash_text() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | awk '{print $1}'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$input" | openssl dgst -sha256 | awk '{print $2}'
    return
  fi
  printf '%s' "$input" | awk '{print length($0)}'
}

trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --retrospective) shift; RETROSPECTIVE_PATH="${1:-}" ;;
    --queue) shift; QUEUE_PATH="${1:-}" ;;
    --results) shift; RESULTS_PATH="${1:-}" ;;
    --enqueue-cmd) shift; ENQUEUE_CMD="${1:-}" ;;
    --team) shift; TEAM="${1:-}" ;;
    --project) shift; PROJECT="${1:-}" ;;
    --labels-base) shift; LABELS_BASE_CSV="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$RETROSPECTIVE_PATH" ] || [ -z "$QUEUE_PATH" ] || [ -z "$RESULTS_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [ ! -f "$RETROSPECTIVE_PATH" ]; then
  jq -n -c '{considered:0,enqueued:0,skipped:0,failed:0,dedup_keys:[],mode:"missing_retrospective"}'
  exit 0
fi

read -r -a ENQUEUE_CMD_ARR <<< "$ENQUEUE_CMD"
if [ "${#ENQUEUE_CMD_ARR[@]}" -eq 0 ]; then
  echo "invalid --enqueue-cmd value" >&2
  exit 1
fi
if ! command -v "${ENQUEUE_CMD_ARR[0]}" >/dev/null 2>&1; then
  echo "enqueue command not found: ${ENQUEUE_CMD_ARR[0]}" >&2
  exit 1
fi

improvements_json="$(jq -c '
  [
    (.proposedImprovements // [])[]
    | select((.severity // "") == "critical" or (.severity // "") == "major")
  ]
' "$RETROSPECTIVE_PATH")"

considered="$(jq -r 'length' <<< "$improvements_json")"
enqueued=0
skipped=0
failed=0
dedup_keys='[]'

while IFS= read -r improvement_json; do
  [ -z "$improvement_json" ] && continue

  severity="$(jq -r '.severity // "major"' <<< "$improvement_json")"
  target_raw="$(jq -r '.target // "workflow"' <<< "$improvement_json")"
  observation_raw="$(jq -r '.observation // "Retrospective improvement"' <<< "$improvement_json")"
  recommendation_raw="$(jq -r '.recommendation // "Apply deterministic workflow fix"' <<< "$improvement_json")"

  source_material="severity=${severity}|target=${target_raw}|observation=${observation_raw}|recommendation=${recommendation_raw}"
  source_hash="$(hash_text "$source_material")"
  dedup_key="retrospective-improvement:${source_hash}"
  dedup_keys="$(jq -c --arg key "$dedup_key" 'if index($key) == null then . + [$key] else . end' <<< "$dedup_keys")"

  target_slug="$(printf '%s' "$target_raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  labels_csv="$LABELS_BASE_CSV"
  if [ -n "$target_slug" ]; then
    labels_csv="${labels_csv},${target_slug}"
  fi

  priority="2"
  if [ "$severity" = "critical" ]; then
    priority="1"
  fi

  observation_short="$(printf '%s' "$observation_raw" | tr '\n' ' ' | cut -c1-90)"
  observation_short="$(trim "$observation_short")"
  [ -n "$observation_short" ] || observation_short="Retrospective improvement"

  title="Ralph improvement (${target_raw}): ${observation_short}"
  description=$(cat <<DESC
## Retrospective Improvement

- Severity: ${severity}
- Target: ${target_raw}
- Observation: ${observation_raw}
- Recommendation: ${recommendation_raw}
- retrospectiveSourceHash: ${source_hash}

Generated from post-run retrospective pipeline.
DESC
)

  enqueue_output_file="$(mktemp)"
  set +e
  if [ -n "$PROJECT" ]; then
    "${ENQUEUE_CMD_ARR[@]}" \
      --queue "$QUEUE_PATH" \
      --results "$RESULTS_PATH" \
      --dedup-key "$dedup_key" \
      --title "$title" \
      --description "$description" \
      --team "$TEAM" \
      --project "$PROJECT" \
      --priority "$priority" \
      --labels "$labels_csv" > "$enqueue_output_file" 2>&1
  else
    "${ENQUEUE_CMD_ARR[@]}" \
      --queue "$QUEUE_PATH" \
      --results "$RESULTS_PATH" \
      --dedup-key "$dedup_key" \
      --title "$title" \
      --description "$description" \
      --team "$TEAM" \
      --priority "$priority" \
      --labels "$labels_csv" > "$enqueue_output_file" 2>&1
  fi
  enqueue_rc=$?
  set -e

  enqueue_output="$(cat "$enqueue_output_file" 2>/dev/null || true)"
  rm -f "$enqueue_output_file"

  if [ "$enqueue_rc" -ne 0 ]; then
    failed=$((failed + 1))
    continue
  fi

  if [ -n "$enqueue_output" ] && jq -e '.' >/dev/null 2>&1 <<< "$enqueue_output"; then
    status="$(jq -r '.status // "unknown"' <<< "$enqueue_output")"
    if [ "$status" = "enqueued" ]; then
      enqueued=$((enqueued + 1))
    elif [ "$status" = "skipped_duplicate" ]; then
      skipped=$((skipped + 1))
    else
      failed=$((failed + 1))
    fi
  else
    failed=$((failed + 1))
  fi
done < <(jq -c '.[]' <<< "$improvements_json")

jq -n -c \
  --argjson considered "$considered" \
  --argjson enqueued "$enqueued" \
  --argjson skipped "$skipped" \
  --argjson failed "$failed" \
  --argjson dedup_keys "$dedup_keys" \
  '
  {
    considered: $considered,
    enqueued: $enqueued,
    skipped: $skipped,
    failed: $failed,
    dedup_keys: $dedup_keys
  }'
