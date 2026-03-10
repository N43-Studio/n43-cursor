#!/usr/bin/env bash
#
# Deterministic per-issue model tier selector for Ralph execution.
#

set -euo pipefail

ISSUE_JSON_PATH=""
POLICY_PATH=""
RUN_LOG_PATH=""
ITERATION=""
FAILURE_COUNT="0"
PRETTY="false"

usage() {
  cat <<'USAGE'
Usage: scripts/select-model-tier.sh --issue-json <path> [options]

Options:
  --issue-json <path>   Issue JSON payload path (required)
  --policy <path>       Routing policy JSON path (optional)
  --run-log <path>      run-log.jsonl path for historical failure signal (optional)
  --iteration <num>     Iteration number for trace metadata (optional)
  --failure-count <n>   Prior non-success attempts for this issue (default: 0)
  --pretty              Pretty-print output JSON
  --help                Show this help
USAGE
}

default_policy_json() {
  jq -n -c '
    {
      version: "1.0",
      thresholds: {
        lowMax: 3.0,
        mediumMax: 6.0
      },
      weights: {
        priority: 1.4,
        estimate: 1.2,
        dependencies: 0.8,
        complexity: 1.0,
        riskKeywords: 1.1,
        historyFailures: 1.3,
        humanRequired: 2.0
      },
      confidence: {
        base: 0.90,
        missingSignalPenalty: 0.14,
        historyBonus: 0.03,
        min: 0.25,
        max: 0.98
      },
      riskKeywords: [
        "migration",
        "rollback",
        "security",
        "auth",
        "billing",
        "payment",
        "incident",
        "production",
        "concurrency",
        "data loss"
      ],
      models: {
        low: "fast",
        medium: "balanced",
        high: "deep"
      },
      fallbackTier: "medium"
    }'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue-json) shift; ISSUE_JSON_PATH="${1:-}" ;;
    --policy) shift; POLICY_PATH="${1:-}" ;;
    --run-log) shift; RUN_LOG_PATH="${1:-}" ;;
    --iteration) shift; ITERATION="${1:-}" ;;
    --failure-count) shift; FAILURE_COUNT="${1:-}" ;;
    --pretty) PRETTY="true" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$ISSUE_JSON_PATH" ]; then
  usage >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [ ! -f "$ISSUE_JSON_PATH" ]; then
  echo "issue json not found: $ISSUE_JSON_PATH" >&2
  exit 1
fi

issue_json="$(jq -c '.' "$ISSUE_JSON_PATH")"
policy_json="$(default_policy_json)"

if ! [[ "$FAILURE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "--failure-count must be an integer >= 0" >&2
  exit 1
fi

if [ -n "$POLICY_PATH" ] && [ -f "$POLICY_PATH" ]; then
  policy_json="$(jq -c '.' "$POLICY_PATH")"
fi

history_json='[]'
if [ -n "$RUN_LOG_PATH" ] && [ -f "$RUN_LOG_PATH" ]; then
  history_json="$(jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | map(fromjson? // {"_invalid": true})
    | map(select(type == "object" and (._invalid // false) != true))
  ' "$RUN_LOG_PATH")"
fi

routing_json="$(
  jq -n -c \
    --argjson issue "$issue_json" \
    --argjson policy "$policy_json" \
    --argjson history "$history_json" \
    --arg iteration "$ITERATION" \
    --argjson prior_failures "$FAILURE_COUNT" \
    '
    def clamp($value; $min; $max):
      if $value < $min then $min
      elif $value > $max then $max
      else $value
      end;

    def parse_priority($issue):
      if ($issue.priority | type) == "number" then $issue.priority
      elif ($issue.priority | type) == "object" and ($issue.priority.value | type) == "number" then $issue.priority.value
      else null end;

    def parse_estimate($issue):
      if (($issue.estimatedPoints // $issue.estimate) | type) == "number" then ($issue.estimatedPoints // $issue.estimate)
      elif (($issue.estimatedPoints // $issue.estimate) | type) == "object"
        and (($issue.estimatedPoints // $issue.estimate).value | type) == "number"
      then ($issue.estimatedPoints // $issue.estimate).value
      else null end;

    def parse_labels($issue):
      (
        if ($issue.labels | type) == "array" then $issue.labels
        elif ($issue.linearLabels | type) == "array" then $issue.linearLabels
        else [] end
      )
      | map(
          if type == "string" then .
          elif type == "object" then (.name // .label // .id // "") | tostring
          else tostring
          end
        )
      | map(select(length > 0));

    def parse_dep_count($issue):
      (
        (if ($issue.dependsOn | type) == "array" then $issue.dependsOn else [] end)
        + (if ($issue.blockedBy | type) == "array" then $issue.blockedBy else [] end)
      ) | length;

    ($issue // {}) as $i
    | ($policy // {}) as $p
    | (($i.issueId // "") | tostring) as $issue_id
    | ($i.description // "" | tostring) as $description
    | ($description | ascii_downcase) as $description_lower
    | ($description | split(" ") | map(select(length > 0)) | length) as $description_words
    | parse_priority($i) as $priority
    | parse_estimate($i) as $estimate
    | parse_labels($i) as $labels
    | parse_dep_count($i) as $dependency_count_raw
    | ($dependency_count_raw | if . > 3 then 3 else . end) as $dependency_count
    | (($labels | index("Human Required")) != null) as $has_human_required
    | (
        ($p.riskKeywords // [])
        | map(select(type == "string" and length > 0))
        | map(select(. as $kw | ($description_lower | contains($kw))))
        | length
      ) as $risk_keyword_hits
    | (
        $history
        | map(select((.issueId // "") == $issue_id))
      ) as $history_same_issue
    | ($history_same_issue | map(select((.result // "") | IN("failure", "human_required"))) | length) as $history_failure_count
    | ($history_same_issue | length) as $history_attempt_count
    | ($prior_failures // 0) as $prior_failure_count
    | (
        if $priority == 1 then 3
        elif $priority == 2 then 2
        elif $priority == 3 then 1
        else 0
        end
      ) as $priority_component
    | (
        if $estimate == null then 0
        elif $estimate <= 2 then 1
        elif $estimate <= 3 then 2
        elif $estimate <= 5 then 3
        else 4
        end
      ) as $estimate_component
    | (
        if $description_words > 180 then 2
        elif $description_words > 80 then 1
        else 0
        end
      ) as $complexity_component
    | (
        ($priority_component * ($p.weights.priority // 1.4))
        + ($estimate_component * ($p.weights.estimate // 1.2))
        + ($dependency_count * ($p.weights.dependencies // 0.8))
        + ($complexity_component * ($p.weights.complexity // 1.0))
        + ($risk_keyword_hits * ($p.weights.riskKeywords // 1.1))
        + ($history_failure_count * ($p.weights.historyFailures // 1.3))
        + (if $has_human_required then ($p.weights.humanRequired // 2.0) else 0 end)
      ) as $score
    | (
        [
          ($priority != null),
          ($estimate != null),
          ($description_words > 0),
          ($dependency_count_raw >= 0)
        ]
        | map(select(. == true))
        | length
      ) as $signal_count
    | (
        ($p.confidence.base // 0.90)
        - ((4 - $signal_count) * ($p.confidence.missingSignalPenalty // 0.14))
        + ((if $history_attempt_count > 3 then 3 else $history_attempt_count end) * ($p.confidence.historyBonus // 0.03))
      ) as $confidence_raw
    | (
        clamp(
          $confidence_raw;
          ($p.confidence.min // 0.25);
          ($p.confidence.max // 0.98)
        )
      ) as $confidence
    | (
        if $signal_count < 2 then true else false end
      ) as $fallback_used
    | (
        if $fallback_used then ($p.fallbackTier // "medium")
        elif $score <= ($p.thresholds.lowMax // 3.0) then "low"
        elif $score <= ($p.thresholds.mediumMax // 6.0) then "medium"
        else "high"
        end
      ) as $score_tier
    | (
        if $prior_failure_count >= 2 then "high"
        elif $prior_failure_count == 1 then "medium"
        else "low"
        end
      ) as $failure_floor_tier
    | (
        if $score_tier == "high" or $failure_floor_tier == "high" then "high"
        elif $score_tier == "medium" or $failure_floor_tier == "medium" then "medium"
        else "low"
        end
      ) as $tier
    | {
        policyVersion: ($p.version // "1.0"),
        issueId: $issue_id,
        iteration: (if $iteration == "" then null else ($iteration | tonumber? // null) end),
        selectedTier: $tier,
        selectedModel: (
          if $tier == "low" then ($p.models.low // "fast")
          elif $tier == "medium" then ($p.models.medium // "balanced")
          else ($p.models.high // "deep")
          end
        ),
        score: (($score * 100 | round) / 100),
        confidence: (($confidence * 100 | round) / 100),
        fallbackUsed: $fallback_used,
        factors: {
          priority: $priority,
          estimate: $estimate,
          dependencyCount: $dependency_count_raw,
          descriptionWords: $description_words,
          riskKeywordHits: $risk_keyword_hits,
          hasHumanRequired: $has_human_required,
          priorFailureCount: $prior_failure_count,
          historyFailureCount: $history_failure_count,
          historyAttemptCount: $history_attempt_count
        },
        rationale: [
          ("score=\((($score * 100 | round) / 100)) tier=\($tier) model=\(
            if $tier == "low" then ($p.models.low // "fast")
            elif $tier == "medium" then ($p.models.medium // "balanced")
            else ($p.models.high // "deep")
            end
          )"),
          ("signals priority=\($priority // "null") estimate=\($estimate // "null") deps=\($dependency_count_raw) words=\($description_words) risk_hits=\($risk_keyword_hits)"),
          ("history attempts=\($history_attempt_count) failures=\($history_failure_count) confidence=\((($confidence * 100 | round) / 100)) fallback=\($fallback_used)")
        ]
      }
    '
)"

if [ "$PRETTY" = "true" ]; then
  jq '.' <<< "$routing_json"
else
  printf '%s\n' "$routing_json"
fi
