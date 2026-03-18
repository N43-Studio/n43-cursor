#!/usr/bin/env bash
#
# Mock delegated issue creator for local/CI contract validation.
#

set -euo pipefail

INTENT_JSON=""
OUTPUT_JSON=""

usage() {
  cat <<'EOF'
Usage: scripts/mock-linear-issue-creator.sh --intent-json <path> --output-json <path>
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --intent-json) shift; INTENT_JSON="${1:-}" ;;
    --output-json) shift; OUTPUT_JSON="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$INTENT_JSON" ] || [ -z "$OUTPUT_JSON" ]; then
  usage >&2
  exit 1
fi

if [ ! -f "$INTENT_JSON" ]; then
  echo "intent json not found: $INTENT_JSON" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi
if ! command -v shasum >/dev/null 2>&1; then
  echo "shasum is required" >&2
  exit 1
fi

dedup_key="$(jq -r '.dedup_key // ""' "$INTENT_JSON")"
[ -n "$dedup_key" ] || { echo "intent missing dedup_key" >&2; exit 1; }

suffix="$(printf '%s' "$dedup_key" | shasum -a 256 | cut -c1-8 | tr '[:lower:]' '[:upper:]')"
issue_id="MOCK-${suffix}"

jq -n \
  --arg issue_id "$issue_id" \
  '
  {
    issue_id: $issue_id,
    url: ("https://linear.app/mock/issue/" + $issue_id)
  }' > "$OUTPUT_JSON"
