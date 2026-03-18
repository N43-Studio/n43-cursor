#!/usr/bin/env bash
#
# Update the global Ralph calibration store from a retrospective artifact.
#

set -euo pipefail

RETROSPECTIVE_PATH=""
OUTPUT_PATH=".cursor/ralph/calibration.json"

usage() {
  cat <<'EOF'
Usage: scripts/update-calibration-store.sh --retrospective <path> [options]

Options:
  --retrospective <path>  Retrospective JSON path (required)
  --output <path>         Calibration JSON output path (default: .cursor/ralph/calibration.json)
  --help                  Show this help
EOF
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --retrospective)
      shift
      RETROSPECTIVE_PATH="${1:-}"
      ;;
    --output)
      shift
      OUTPUT_PATH="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$RETROSPECTIVE_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [ ! -f "$RETROSPECTIVE_PATH" ]; then
  echo "retrospective not found: $RETROSPECTIVE_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

existing_json='{}'
if [ -f "$OUTPUT_PATH" ]; then
  existing_json="$(jq -c '.' "$OUTPUT_PATH" 2>/dev/null || printf '{}')"
fi

generated_at="$(now_iso)"

updated_json="$(
  jq -n -c \
    --arg generated_at "$generated_at" \
    --arg retrospective_path "$RETROSPECTIVE_PATH" \
    --argjson existing "$existing_json" \
    --slurpfile retrospective "$RETROSPECTIVE_PATH" \
    '
    def bucket_files_changed($count):
      if $count >= 5 then "5+"
      elif $count >= 3 then "3-4"
      elif $count >= 1 then "1-2"
      else "0"
      end;

    def bucket_duration($ms):
      if $ms >= 300000 then "300s+"
      elif $ms >= 120000 then "120-299s"
      elif $ms >= 60000 then "60-119s"
      elif $ms >= 1 then "1-59s"
      else "0"
      end;

    def bucket_estimate($points):
      if $points == null then "unknown"
      else ($points | tostring)
      end;

    def summarize_buckets($entries; $field):
      reduce $entries[] as $entry
        ({};
          .[$entry[$field]] += [{
            tokensPerPoint: $entry.tokensPerEstimatedPoint,
            durationMs: ($entry.actualDurationMs // 0)
          }]
        )
      | with_entries(
          .value |= {
            count: length,
            avgTokensPerPoint: ((map(.tokensPerPoint) | add) / length | round),
            avgDurationMs: ((map(.durationMs) | add) / length | round)
          }
        );

    ($existing // {}) as $prev
    | ($retrospective[0] // {}) as $retro
    | ($prev.history // []) as $prev_history
    | (
        ($retro.estimationAccuracy // [])
        | map({
            runId: ($retro.runId // null),
            generatedAt: ($retro.generatedAt // $generated_at),
            issueId: .issueId,
            issueTitle: (.issueTitle // ""),
            estimatedPoints: (.estimatedPoints // null),
            actualTokens: (.actualTokens // 0),
            actualInputTokens: (.actualInputTokens // 0),
            actualOutputTokens: (.actualOutputTokens // 0),
            tokenSources: (.tokenSources // []),
            actualDurationMs: (.actualDurationMs // 0),
            actualFilesChanged: (.actualFilesChanged // 0),
            reportedTokenAttempts: (
              if (.reportedTokenAttempts | type) == "number" then .reportedTokenAttempts
              elif .tokensPerEstimatedPoint != null then 1
              else 0
              end
            ),
            missingTokenAttempts: (.missingTokenAttempts // 0),
            tokenTelemetryStatus: (
              if (.tokenTelemetryStatus | type) == "string" and ((.tokenTelemetryStatus | length) > 0) then .tokenTelemetryStatus
              elif .tokensPerEstimatedPoint != null then "reported"
              else "missing"
              end
            ),
            hasRealTelemetry: (
              (.tokenSources // []) | any(. == "codex_api" or . == "cursor_api")
            ),
            finalResult: (.finalResult // "unknown"),
            passed: ((.finalResult // "") == "success"),
            tokensPerEstimatedPoint: (
              if (.tokensPerEstimatedPoint != null and .tokensPerEstimatedPoint > 0)
              then .tokensPerEstimatedPoint
              else null
              end
            ),
            calibrationUsable: (
              (.tokensPerEstimatedPoint != null)
              and (.tokensPerEstimatedPoint > 0)
            ),
            issueCharacteristics: {
              estimateBucket: bucket_estimate(.estimatedPoints // null),
              filesChangedBucket: bucket_files_changed(.actualFilesChanged // 0),
              durationBucket: bucket_duration(.actualDurationMs // 0),
              finalResult: (.finalResult // "unknown")
            },
            source: {
              retrospectivePath: $retrospective_path,
              prdPath: ($retro.source.prdPath // null)
            },
            dedupKey: (($retro.runId // "no-run-id") + ":" + (.issueId // "unknown"))
          })
      ) as $new_history
    | (
        ($prev_history + $new_history)
        | sort_by(.dedupKey)
        | group_by(.dedupKey)
        | map(.[-1])
      ) as $history
    | ($history | map(select(.calibrationUsable == true))) as $usable
    | ($usable | map(select(.hasRealTelemetry == true))) as $real_telemetry
    | ($usable | map(select(.hasRealTelemetry != true))) as $estimated_telemetry
    | (
        if ($usable | length) > 0 then
          if ($real_telemetry | length) > 0 then
            (
              (($real_telemetry | map(.tokensPerEstimatedPoint * 2) | add) + ($estimated_telemetry | map(.tokensPerEstimatedPoint) | add // 0))
              / (($real_telemetry | length) * 2 + ($estimated_telemetry | length))
            ) | round
          else
            ((($usable | map(.tokensPerEstimatedPoint) | add) / ($usable | length)) | round)
          end
        else
          ($prev.global.tokensPerPoint // 3200)
        end
      ) as $global_tokens_per_point
    | {
        calibrationVersion: "2026-03-18.v1",
        updatedAt: $generated_at,
        global: {
          tokensPerPoint: $global_tokens_per_point,
          usableSampleCount: ($usable | length),
          realTelemetrySampleCount: ($real_telemetry | length),
          estimatedTelemetrySampleCount: ($estimated_telemetry | length),
          totalSampleCount: ($history | length),
          sourceRetrospectivePath: $retrospective_path
        },
        runs: (
          (($prev.runs // []) + [{
            runId: ($retro.runId // null),
            generatedAt: ($retro.generatedAt // $generated_at),
            sourceRetrospectivePath: $retrospective_path,
            issueCount: (($retro.estimationAccuracy // []) | length),
            usableSampleCount: ($new_history | map(select(.calibrationUsable == true)) | length),
            tokensPerPoint: (
              if ($new_history | map(select(.calibrationUsable == true)) | length) > 0 then
                ((($new_history | map(select(.calibrationUsable == true) | .tokensPerEstimatedPoint) | add) / ($new_history | map(select(.calibrationUsable == true)) | length)) | round)
              else null
              end
            )
          }])
          | map(select(.runId != null or .sourceRetrospectivePath != null))
          | sort_by((.generatedAt // ""))
        ),
        history: $history,
        estimationAccuracy: $history,
        buckets: {
          filesChanged: summarize_buckets(($usable | map(. + {filesChangedBucket: .issueCharacteristics.filesChangedBucket})); "filesChangedBucket"),
          estimate: summarize_buckets(($usable | map(. + {estimateBucket: .issueCharacteristics.estimateBucket})); "estimateBucket")
        }
      }
    '
)"

printf '%s\n' "$updated_json" > "$OUTPUT_PATH"

jq -n -c \
  --arg path "$OUTPUT_PATH" \
  --argjson calibration "$updated_json" \
  '
  {
    updated: true,
    path: $path,
    samples_total: ($calibration.history | length),
    usable_samples: ($calibration.global.usableSampleCount // 0),
    tokens_per_point: ($calibration.global.tokensPerPoint // null)
  }
  '
