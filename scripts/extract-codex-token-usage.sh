#!/usr/bin/env bash
#
# Best-effort extraction of token usage from codex exec --json event streams.
# Emits either a positive integer token count or `null`.
#

set -euo pipefail

EVENTS_PATH=""
FORMAT="scalar"

usage() {
  cat <<'EOF'
Usage: scripts/extract-codex-token-usage.sh --events <path> [--structured]

Options:
  --events <path>  Path to codex exec --json event stream file
  --structured     Output structured JSON with input/output/total/source
                   Default: output scalar total integer or null
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --events)
      shift
      EVENTS_PATH="${1:-}"
      ;;
    --structured)
      FORMAT="structured"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

emit_unavailable() {
  if [ "$FORMAT" = "structured" ]; then
    printf '{"input_tokens":0,"output_tokens":0,"total_tokens":0,"source":"unavailable"}\n'
  else
    printf 'null\n'
  fi
}

if [ -z "$EVENTS_PATH" ] || [ ! -f "$EVENTS_PATH" ]; then
  emit_unavailable
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  emit_unavailable
  exit 0
fi

if [ "$FORMAT" = "structured" ]; then
  structured_result="$(jq -Rsc '
    def to_int:
      if type == "number" then floor
      elif type == "string" and test("^[0-9]+$") then tonumber
      else null
      end;

    def extract_usage($obj):
      if $obj == null then null
      elif ($obj.input_tokens != null or $obj.output_tokens != null) then
        {input: (($obj.input_tokens // 0) | to_int), output: (($obj.output_tokens // 0) | to_int), total: (($obj.total_tokens // null) | to_int)}
      elif ($obj.inputTokens != null or $obj.outputTokens != null) then
        {input: (($obj.inputTokens // 0) | to_int), output: (($obj.outputTokens // 0) | to_int), total: (($obj.totalTokens // null) | to_int)}
      elif ($obj.total_tokens != null or $obj.totalTokens != null) then
        {input: null, output: null, total: (($obj.total_tokens // $obj.totalTokens // null) | to_int)}
      else null
      end;

    def candidate_usages($event):
      [
        extract_usage($event.usage),
        extract_usage($event.response.usage),
        extract_usage($event.result.usage),
        extract_usage($event.token_usage),
        extract_usage($event.tokenUsage),
        extract_usage($event.event.response.usage)
      ]
      | map(select(. != null))
      | map(select((.total != null and .total > 0) or (.input != null and .input > 0) or (.output != null and .output > 0)));

    split("\n")
    | map(select(length > 0))
    | map(try fromjson catch empty)
    | map(candidate_usages(.))
    | add // []
    | if length == 0 then
        {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0, "source": "unavailable"}
      else
        (map(.total // ((.input // 0) + (.output // 0))) | max) as $max_total
        | (map(select((.total // ((.input // 0) + (.output // 0))) == $max_total)) | .[0]) as $best
        | {
            input_tokens: ($best.input // 0),
            output_tokens: ($best.output // 0),
            total_tokens: (
              if $best.total != null then $best.total
              else (($best.input // 0) + ($best.output // 0))
              end
            ),
            source: "codex_api"
          }
      end
  ' "$EVENTS_PATH" 2>/dev/null || printf '{"input_tokens":0,"output_tokens":0,"total_tokens":0,"source":"unavailable"}')"

  printf '%s\n' "$structured_result"
else
  tokens_used="$(jq -Rsc '
    def to_int:
      if type == "number" then floor
      elif type == "string" and test("^[0-9]+$") then tonumber
      else null
      end;

    def summed_usage($obj):
      if (($obj.input_tokens // null) != null or ($obj.output_tokens // null) != null) then
        (($obj.input_tokens // 0) + ($obj.output_tokens // 0))
      elif (($obj.inputTokens // null) != null or ($obj.outputTokens // null) != null) then
        (($obj.inputTokens // 0) + ($obj.outputTokens // 0))
      else
        null
      end;

    def candidate_tokens($event):
      [
        $event.usage.total_tokens,
        $event.usage.totalTokens,
        $event.response.usage.total_tokens,
        $event.response.usage.totalTokens,
        $event.result.usage.total_tokens,
        $event.result.usage.totalTokens,
        $event.metrics.tokens_used,
        $event.metrics.tokensUsed,
        $event.token_usage.total_tokens,
        $event.tokenUsage.totalTokens,
        $event.event.response.usage.total_tokens,
        $event.event.response.usage.totalTokens,
        summed_usage($event.usage),
        summed_usage($event.response.usage),
        summed_usage($event.result.usage),
        summed_usage($event.event.response.usage)
      ]
      | map(to_int)
      | map(select(. != null and . > 0));

    split("\n")
    | map(select(length > 0))
    | map(try fromjson catch empty)
    | map(candidate_tokens(.))
    | add
    | if length > 0 then max else null end
  ' "$EVENTS_PATH" 2>/dev/null || printf 'null')"

  if [[ "$tokens_used" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$tokens_used"
  else
    printf 'null\n'
  fi
fi
