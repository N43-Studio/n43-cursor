#!/usr/bin/env bash
#
# Deterministic issue metadata scorer for Ralph issue-generation flows.
#

set -euo pipefail

INPUT_PATH=""
CALIBRATION_PATH=".cursor/ralph/calibration.json"
PRETTY="false"

usage() {
  cat <<'USAGE'
Usage: scripts/score-issue-metadata.sh [options]

Options:
  --input <path>         Input issue-draft JSON path (default: stdin)
  --calibration <path>   Calibration JSON path (default: .cursor/ralph/calibration.json)
  --pretty               Pretty-print output JSON
  --help                 Show this help

Input JSON supports fields such as:
  title, description, acceptanceCriteria, dependsOn, blockedBy, blocks,
  files, filesToCreate, filesToModify, validation, riskFlags
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --input) shift; INPUT_PATH="${1:-}" ;;
    --calibration) shift; CALIBRATION_PATH="${1:-}" ;;
    --pretty) PRETTY="true" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

input_json=""
if [ -n "$INPUT_PATH" ]; then
  if [ ! -f "$INPUT_PATH" ]; then
    echo "input not found: $INPUT_PATH" >&2
    exit 1
  fi
  input_json="$(jq -c '.' "$INPUT_PATH")"
else
  stdin_payload="$(cat)"
  if [ -z "$stdin_payload" ]; then
    echo "input JSON required via stdin or --input" >&2
    exit 1
  fi
  input_json="$(jq -c '.' <<< "$stdin_payload")"
fi

calibration_json='{}'
if [ -n "$CALIBRATION_PATH" ] && [ -f "$CALIBRATION_PATH" ]; then
  calibration_json="$(jq -c '.' "$CALIBRATION_PATH" 2>/dev/null || printf '{}')"
fi

output_json="$(
  jq -n -c \
    --argjson issue "$input_json" \
    --argjson calibration "$calibration_json" \
    '
    def arr($v):
      if $v == null then []
      elif ($v | type) == "array" then $v
      else [$v]
      end;

    def clean_str:
      tostring | gsub("\\s+"; " ") | gsub("^[ ]+|[ ]+$"; "");

    def clamp($value; $min; $max):
      if $value < $min then $min
      elif $value > $max then $max
      else $value
      end;

    ($issue // {}) as $i
    | ([
        ($i.title // null),
        ($i.objective // null),
        ($i.context // null),
        ($i.description // null),
        ($i.implementationNotes // null)
      ]
      | map(select(. != null) | clean_str)
      | join("\n")) as $text
    | ($text | ascii_downcase) as $text_lower
    | ($text_lower | split(" ") | map(select(length > 0)) | length) as $description_word_count
    | ((
        arr($i.files)
        + arr($i.filesToCreate)
        + arr($i.filesToModify)
        + (if ($i.implementation | type) == "object" then arr($i.implementation.files) else [] end)
      )
      | map(clean_str)
      | map(select(length > 0))
      | unique) as $files
    | (arr($i.acceptanceCriteria)
      | map(clean_str)
      | map(select(length > 0))) as $acceptance_from_array
    | (($i.description // "")
      | tostring
      | split("\n")
      | map(select(test("^\\s*- \\[ \\] ")))) as $acceptance_from_markdown
    | (if ($acceptance_from_array | length) > 0 then $acceptance_from_array else $acceptance_from_markdown end) as $acceptance
    | (
        (
          arr($i.dependsOn)
          + arr($i.blockedBy)
          + arr($i.blocks)
          + (if ($i.dependencies | type) == "object" then
              arr($i.dependencies.dependsOn) + arr($i.dependencies.blockedBy) + arr($i.dependencies.blocks)
            else [] end)
        )
        | map(clean_str)
        | map(select(length > 0))
        | unique
      ) as $dependencies
    | (
        if ($i.validation | type) == "object" then
          [
            ($i.validation.lint // null),
            ($i.validation.typecheck // null),
            ($i.validation.test // null),
            ($i.validation.build // null)
          ]
          | map(select(. != null))
          | map(clean_str)
          | map(select(length > 0))
          | length
        else 0 end
      ) as $validation_from_object
    | (
        ["lint", "typecheck", "test", "build"]
        | map(select(. as $keyword | ($text_lower | contains($keyword))))
        | length
      ) as $validation_from_text
    | (
        if $validation_from_object > 0 then $validation_from_object else $validation_from_text end
      ) as $validation_count
    | (
        ["migration", "rollback", "security", "auth", "billing", "payment", "data loss", "concurrency", "production", "incident"]
        | map(select(. as $keyword | ($text_lower | contains($keyword))))
        | length
      ) as $risk_keyword_count
    | ((arr($i.riskFlags) | map(clean_str) | map(select(length > 0)) | unique | length) + $risk_keyword_count) as $risk_count
    | (
        if $description_word_count <= 80 then 0
        elif $description_word_count <= 180 then 1
        else 2
        end
      ) as $complexity_band
    | (
        1200
        + (($files | length) * 650)
        + (($acceptance | length) * 320)
        + (($dependencies | length) * 280)
        + ($validation_count * 250)
        + ($complexity_band * 900)
        + ($risk_count * 700)
      ) as $raw_tokens
    | (
        (
          [
            ($calibration.tokensPerPoint // null),
            ($calibration.global.tokensPerPoint // null)
          ]
          | map(select(type == "number" and . > 0))
        ) as $explicit_points
        | (
            arr($calibration.history) + arr($calibration.runs) + arr($calibration.estimationAccuracy)
            | map(.tokensPerEstimatedPoint // .tokensPerPoint // null)
            | map(select(type == "number" and . > 0))
          ) as $observed_points
        | (
            if ($explicit_points | length) > 0 then $explicit_points[0]
            elif ($observed_points | length) > 0 then (($observed_points | add) / ($observed_points | length))
            else 3200
            end
          )
      ) as $tokens_per_point
    | (clamp(($tokens_per_point / 3200); 0.70; 1.60)) as $calibration_multiplier
    | (($raw_tokens * $calibration_multiplier) | round) as $estimated_tokens
    | (
        if $estimated_tokens <= 3200 then 1
        elif $estimated_tokens <= 6400 then 2
        elif $estimated_tokens <= 9600 then 3
        elif $estimated_tokens <= 16000 then 5
        else 8
        end
      ) as $estimate
    | (
        ($risk_count * 2)
        + ($dependencies | length)
        + (if $estimate >= 5 then 2 else 0 end)
        + (if $validation_count >= 3 then 1 else 0 end)
        + (if $complexity_band == 2 then 1 else 0 end)
      ) as $priority_score
    | (
        if $priority_score >= 7 then 1
        elif $priority_score >= 4 then 2
        elif $priority_score >= 2 then 3
        else 4
        end
      ) as $priority
    | (
        0.95
        - (if ($acceptance | length) == 0 then 0.20 else 0 end)
        - (if ($files | length) == 0 then 0.20 else 0 end)
        - (if $description_word_count < 40 then 0.20 else 0 end)
        - (if ($dependencies | length) == 0 then 0.10 else 0 end)
        - (if $validation_count == 0 then 0.10 else 0 end)
      ) as $confidence_raw
    | (clamp($confidence_raw; 0.20; 0.95)) as $confidence
    | {
        rubricVersion: "2026-03-10.v1",
        priority: $priority,
        estimate: $estimate,
        estimatedPoints: $estimate,
        estimatedTokens: $estimated_tokens,
        confidence: (($confidence * 100 | round) / 100),
        lowConfidence: ($confidence < 0.60),
        signals: {
          filesCount: ($files | length),
          acceptanceCount: ($acceptance | length),
          dependencyCount: ($dependencies | length),
          validationCount: $validation_count,
          descriptionWordCount: $description_word_count,
          complexityBand: $complexity_band,
          riskCount: $risk_count
        },
        calibration: {
          enabled: ($tokens_per_point != 3200),
          tokensPerPoint: (($tokens_per_point | round)),
          multiplier: (($calibration_multiplier * 1000 | round) / 1000)
        },
        rationale: [
          ("signals files=\(($files | length)), acceptance=\(($acceptance | length)), deps=\(($dependencies | length)), validation=\($validation_count), complexity_band=\($complexity_band), risk=\($risk_count)"),
          ("tokens raw=\($raw_tokens), multiplier=\((($calibration_multiplier * 1000 | round) / 1000)), estimated=\($estimated_tokens)"),
          ("mapping estimate=\($estimate), priority_score=\($priority_score), priority=\($priority)"),
          ("confidence=\((($confidence * 100 | round) / 100)), low_confidence=\($confidence < 0.60)")
        ]
      }
    '
)"

if [ "$PRETTY" = "true" ]; then
  jq '.' <<< "$output_json"
else
  printf '%s\n' "$output_json"
fi
