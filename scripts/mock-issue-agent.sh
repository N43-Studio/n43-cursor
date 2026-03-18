#!/usr/bin/env bash
#
# Deterministic smoke-only implementation of the CLI issue execution contract.
# Useful for local and CI fixture runs of scripts/ralph-run.sh.
#

set -euo pipefail

INPUT_JSON=""
OUTPUT_JSON=""

usage() {
  cat <<'EOF'
Usage: scripts/mock-issue-agent.sh --input-json <path> --output-json <path>
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --input-json)
      shift
      INPUT_JSON="${1:-}"
      ;;
    --output-json)
      shift
      OUTPUT_JSON="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 30
      ;;
  esac
  shift
done

if [ -z "$INPUT_JSON" ] || [ -z "$OUTPUT_JSON" ]; then
  usage >&2
  exit 30
fi

if [ ! -f "$INPUT_JSON" ]; then
  echo "input json not found: $INPUT_JSON" >&2
  exit 30
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 30
fi

issue_id="$(jq -r '.issue.id // empty' "$INPUT_JSON")"
iteration="$(jq -r '.iteration // 0' "$INPUT_JSON")"
start_ms=$(( $(date +%s) * 1000 ))

if [ -z "$issue_id" ] || [ "$iteration" = "0" ]; then
  echo "invalid input contract" >&2
  exit 30
fi

end_ms=$(( $(date +%s) * 1000 ))
duration_ms=$((end_ms - start_ms))

jq -n \
  --arg issue_id "$issue_id" \
  --argjson iteration "$iteration" \
  --argjson duration_ms "$duration_ms" \
  '
  {
    contract_version: "1.0",
    issue_id: $issue_id,
    iteration: $iteration,
    outcome: "success",
    exit_code: 0,
    failure_category: null,
    retryable: false,
    retry_after_seconds: null,
    handoff_required: false,
    handoff: null,
    summary: "Smoke-only mock agent completed issue successfully",
    validation_results: {
      lint: "pass",
      typecheck: "pass",
      test: "pass",
      build: "pass"
    },
    artifacts: {
      commit_hash: null,
      pr_url: null,
      files_changed: []
    },
    metrics: {
      duration_ms: $duration_ms,
      tokens_used: 0
    }
  }
  ' > "$OUTPUT_JSON"

exit 0
