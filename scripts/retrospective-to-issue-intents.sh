#!/usr/bin/env bash
#
# Convert retrospective proposed improvements into delegated issue-creation intents.
#

set -euo pipefail

RETROSPECTIVE_PATH=""
QUEUE_PATH=""
RESULTS_PATH=""
ENQUEUE_CMD="scripts/issue-intent-enqueue.sh"
METADATA_SCORER_CMD="scripts/score-issue-metadata.sh"
TEAM="Studio"
PROJECT=""
LABELS_BASE_CSV="Ralph,PRD Ready,Agent Generated,Improvement"

usage() {
  cat <<'USAGE'
Usage: scripts/retrospective-to-issue-intents.sh [options]

Options:
  --retrospective <path>  Retrospective JSON path (required)
  --queue <path>          Intent queue JSONL path (required)
  --results <path>        Intent result JSONL path (required)
  --enqueue-cmd <cmd>     Intent enqueue command (default: scripts/issue-intent-enqueue.sh)
  --metadata-scorer-cmd <cmd>
                          Metadata scorer command (default: scripts/score-issue-metadata.sh)
  --team <name>           Linear team key/name (default: Studio)
  --project <name>        Linear project identifier/name (optional)
  --labels-base <csv>     Base labels CSV (default: Ralph,PRD Ready,Agent Generated,Improvement)
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
    --metadata-scorer-cmd) shift; METADATA_SCORER_CMD="${1:-}" ;;
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

read -r -a METADATA_SCORER_CMD_ARR <<< "$METADATA_SCORER_CMD"
if [ "${#METADATA_SCORER_CMD_ARR[@]}" -eq 0 ]; then
  echo "invalid --metadata-scorer-cmd value" >&2
  exit 1
fi
if ! command -v "${METADATA_SCORER_CMD_ARR[0]}" >/dev/null 2>&1; then
  echo "metadata scorer command not found: ${METADATA_SCORER_CMD_ARR[0]}" >&2
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

  severity_priority="2"
  if [ "$severity" = "critical" ]; then
    severity_priority="1"
  fi

  observation_short="$(printf '%s' "$observation_raw" | tr '\n' ' ' | cut -c1-90)"
  observation_short="$(trim "$observation_short")"
  [ -n "$observation_short" ] || observation_short="Retrospective improvement"

  title="Ralph improvement (${target_raw}): ${observation_short}"

  acceptance_one="Implement the retrospective improvement in ${target_raw} without regressing existing Ralph run behavior."
  acceptance_two="Document any workflow or contract updates required by this improvement."
  acceptance_three="Add or update deterministic validation coverage for the improvement path."

  metadata_input_file="$(mktemp)"
  jq -n \
    --arg title "$title" \
    --arg description "$observation_raw" \
    --arg target "$target_raw" \
    --arg recommendation "$recommendation_raw" \
    --arg severity "$severity" \
    --argjson acceptance "$(jq -n -c --arg one "$acceptance_one" --arg two "$acceptance_two" --arg three "$acceptance_three" '[$one, $two, $three]')" \
    '
    {
      title: $title,
      objective: ("Address retrospective finding for " + $target),
      context: $description,
      description: $recommendation,
      acceptanceCriteria: $acceptance,
      validation: {
        lint: "required",
        typecheck: "required",
        test: "required",
        build: "required"
      },
      riskFlags: (
        if $severity == "critical" then
          ["critical-retrospective-improvement"]
        else
          ["major-retrospective-improvement"]
        end
      )
    }' > "$metadata_input_file"

  metadata_output_file="$(mktemp)"
  set +e
  "${METADATA_SCORER_CMD_ARR[@]}" --input "$metadata_input_file" > "$metadata_output_file" 2>/dev/null
  metadata_rc=$?
  set -e

  if [ "$metadata_rc" -eq 0 ] && jq -e '.' "$metadata_output_file" >/dev/null 2>&1; then
    metadata_json="$(jq -c '.' "$metadata_output_file")"
  else
    if [ "$severity" = "critical" ]; then
      metadata_json='{"priority":1,"estimate":3,"estimatedTokens":9600,"confidence":0.68,"lowConfidence":false,"signals":{},"rationale":["fallback metadata applied because scorer execution failed"]}'
    else
      metadata_json='{"priority":2,"estimate":2,"estimatedTokens":6400,"confidence":0.68,"lowConfidence":false,"signals":{},"rationale":["fallback metadata applied because scorer execution failed"]}'
    fi
  fi

  rm -f "$metadata_input_file" "$metadata_output_file"

  scored_priority="$(jq -r '.priority // empty' <<< "$metadata_json")"
  priority="$severity_priority"
  if [[ "$scored_priority" =~ ^[0-9]+$ ]] && [ "$scored_priority" -lt "$severity_priority" ]; then
    priority="$scored_priority"
  fi

  estimate="$(jq -r '.estimate // 2' <<< "$metadata_json")"
  if ! [[ "$estimate" =~ ^[0-9]+$ ]]; then
    estimate="2"
  fi

  estimated_tokens="$(jq -r '.estimatedTokens // 6400' <<< "$metadata_json")"
  if ! [[ "$estimated_tokens" =~ ^[0-9]+$ ]]; then
    estimated_tokens="6400"
  fi

  confidence="$(jq -r '.confidence // 0.68' <<< "$metadata_json")"
  if ! [[ "$confidence" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    confidence="0.68"
  fi

  low_confidence="$(jq -r '.lowConfidence // false' <<< "$metadata_json")"
  if [ "$low_confidence" != "true" ] && [ "$low_confidence" != "false" ]; then
    low_confidence="false"
  fi

  rubric_factors="$(jq -c '.signals // {}' <<< "$metadata_json")"
  if [ -z "$rubric_factors" ]; then
    rubric_factors='{}'
  fi

  rationale_lines="$(jq -r '
    (.rationale // [])
    | map(select(type == "string" and length > 0) | "- " + .)
    | if length == 0 then "- scorer rationale unavailable" else .[] end
  ' <<< "$metadata_json")"

  description=$(cat <<DESC
## Goal
Implement the retrospective improvement for ${target_raw} so future Ralph runs do not require manual cleanup for this finding.

## Context
The retrospective identified a ${severity} issue in ${target_raw}.
Observation: ${observation_raw}
Recommendation: ${recommendation_raw}

## Scope
- Apply the recommendation to the relevant scripts/contracts for ${target_raw}.
- Preserve deterministic idempotency and run-loop compatibility.
- Keep unrelated issue flows unchanged.

## Acceptance Criteria
- [ ] ${acceptance_one}
- [ ] ${acceptance_two}
- [ ] ${acceptance_three}

## Validation
- \`lint\`: required
- \`typecheck\`: required
- \`test\`: required
- \`build\`: required

## Metadata Rationale
- \`priority=${priority}\`
- \`estimate=${estimate}\`
- \`estimatedTokens=${estimated_tokens}\`
- \`confidence=${confidence}\`
- \`lowConfidence=${low_confidence}\`
- \`rubricFactors=${rubric_factors}\`
- \`retrospectiveSourceHash=${source_hash}\`

${rationale_lines}

## Retrospective Trace
- Severity: ${severity}
- Target: ${target_raw}
- Observation: ${observation_raw}
- Recommendation: ${recommendation_raw}

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
      --estimate "$estimate" \
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
      --estimate "$estimate" \
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
