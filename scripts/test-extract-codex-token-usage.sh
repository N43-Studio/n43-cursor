#!/usr/bin/env bash
#
# Unit-style checks for extract-codex-token-usage.sh.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTOR="$SCRIPT_DIR/extract-codex-token-usage.sh"

FAILURES=0
TMP_ROOT="$(mktemp -d /tmp/extract-codex-token-usage.XXXXXX)"

cleanup() {
  rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1"
  FAILURES=$((FAILURES + 1))
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$message"
  else
    fail "$message (expected=$expected actual=$actual)"
  fi
}

run_case() {
  local case_name="$1"
  local payload="$2"
  local expected="$3"
  local events_path="$TMP_ROOT/$case_name.jsonl"

  printf '%s\n' "$payload" > "$events_path"
  local actual
  actual="$("$EXTRACTOR" --events "$events_path")"
  assert_eq "$actual" "$expected" "$case_name"
}

if [ ! -x "$EXTRACTOR" ]; then
  fail "extractor script must exist and be executable"
fi

run_case \
  "response-total-tokens" \
  '{"type":"response.completed","response":{"usage":{"total_tokens":1234}}}' \
  "1234"

run_case \
  "input-output-sum" \
  '{"type":"response.completed","usage":{"input_tokens":700,"output_tokens":55}}' \
  "755"

run_case \
  "mixed-events-max-positive" \
  $'not-json\n{"usage":{"total_tokens":0}}\n{"response":{"usage":{"total_tokens":2500}}}\n{"usage":{"total_tokens":1800}}' \
  "2500"

run_case \
  "no-telemetry" \
  $'{"type":"event","message":"no usage"}\n' \
  "null"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS codex token extractor checks passed"
  exit 0
fi

echo "RESULT FAIL codex token extractor checks failed: $FAILURES"
exit 1
