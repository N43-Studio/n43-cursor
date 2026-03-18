#!/usr/bin/env bash
#
# Standalone dispatch event emitter.
# Produces canonical dispatch JSON payloads per contracts/ralph/core/dispatch-protocol.md.
#
# Supports: claim, heartbeat, complete event types.
# Output: writes to --output <path> if provided, otherwise stdout.

set -euo pipefail

EVENT_TYPE=""
DISPATCH_MODE="standalone"
DISPATCH_ID=""
RUN_ID=""
ISSUE_ID=""
ATTEMPT=""
WORKFLOW_MODE="independent"
OUTCOME=""
EXIT_CODE=""
FAILURE_CATEGORY=""
RETRYABLE=""
RESULT_PATH=""
PHASE=""
SUMMARY=""
WORKER_ID=""
WORKER_SURFACE=""
WORKER_MODEL=""
HEARTBEAT_INTERVAL_SECONDS=300
TTL_SECONDS=900
OUTPUT_PATH=""

usage() {
  cat <<'EOF'
Usage: scripts/emit-dispatch-event.sh --event <type> --dispatch-id <id> --run-id <id> --issue-id <id> [options]

Required:
  --event <type>        Event type: claim|heartbeat|complete
  --dispatch-id <id>    Dispatch identifier
  --run-id <id>         Run identifier
  --issue-id <id>       Issue identifier

Options (claim):
  --attempt <num>       Attempt number (default: 1)
  --dispatch-mode <m>   standalone|orchestrated (default: standalone)
  --workflow-mode <m>   independent|human-in-the-loop (default: independent)
  --worker-id <id>      Worker identifier
  --worker-surface <s>  Worker surface (cursor, codex, etc.)
  --worker-model <m>    Worker model name
  --heartbeat-interval <s> Heartbeat interval in seconds (default: 300)
  --ttl <s>             Lease TTL in seconds (default: 900)

Options (heartbeat):
  --phase <phase>       Current execution phase
  --summary <text>      Human-readable progress summary

Options (complete):
  --outcome <outcome>   success|failure
  --exit-code <num>     Exit code from worker
  --failure-category <c> Failure category (if failure)
  --retryable <bool>    true|false
  --result-path <path>  Path to result payload

Output:
  --output <path>       Write to file (append). Default: stdout.
  --help                Show this help
EOF
}

fail() {
  echo "ERROR: $1" >&2
  exit "${2:-1}"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --event) shift; EVENT_TYPE="${1:-}" ;;
    --dispatch-mode) shift; DISPATCH_MODE="${1:-}" ;;
    --dispatch-id) shift; DISPATCH_ID="${1:-}" ;;
    --run-id) shift; RUN_ID="${1:-}" ;;
    --issue-id) shift; ISSUE_ID="${1:-}" ;;
    --attempt) shift; ATTEMPT="${1:-}" ;;
    --workflow-mode) shift; WORKFLOW_MODE="${1:-}" ;;
    --outcome) shift; OUTCOME="${1:-}" ;;
    --exit-code) shift; EXIT_CODE="${1:-}" ;;
    --failure-category) shift; FAILURE_CATEGORY="${1:-}" ;;
    --retryable) shift; RETRYABLE="${1:-}" ;;
    --result-path) shift; RESULT_PATH="${1:-}" ;;
    --phase) shift; PHASE="${1:-}" ;;
    --summary) shift; SUMMARY="${1:-}" ;;
    --worker-id) shift; WORKER_ID="${1:-}" ;;
    --worker-surface) shift; WORKER_SURFACE="${1:-}" ;;
    --worker-model) shift; WORKER_MODEL="${1:-}" ;;
    --heartbeat-interval) shift; HEARTBEAT_INTERVAL_SECONDS="${1:-}" ;;
    --ttl) shift; TTL_SECONDS="${1:-}" ;;
    --output) shift; OUTPUT_PATH="${1:-}" ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift
done

[ -n "$EVENT_TYPE" ] || fail "--event is required"
[ -n "$DISPATCH_ID" ] || fail "--dispatch-id is required"
[ -n "$RUN_ID" ] || fail "--run-id is required"
[ -n "$ISSUE_ID" ] || fail "--issue-id is required"

case "$EVENT_TYPE" in
  claim|heartbeat|complete) ;;
  *) fail "--event must be claim|heartbeat|complete" ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required"
fi

timestamp="$(now_iso)"
payload=""

case "$EVENT_TYPE" in
  claim)
    [ -n "$ATTEMPT" ] || ATTEMPT=1
    payload="$(jq -n -c \
      --arg contract_version "1.0" \
      --arg event_type "claim" \
      --arg dispatch_mode "$DISPATCH_MODE" \
      --arg dispatch_id "$DISPATCH_ID" \
      --arg run_id "$RUN_ID" \
      --arg issue_id "$ISSUE_ID" \
      --argjson attempt "$ATTEMPT" \
      --arg workflow_mode "$WORKFLOW_MODE" \
      --arg worker_id "$WORKER_ID" \
      --arg worker_surface "$WORKER_SURFACE" \
      --arg worker_model "$WORKER_MODEL" \
      --argjson heartbeat_interval "$HEARTBEAT_INTERVAL_SECONDS" \
      --argjson ttl "$TTL_SECONDS" \
      --arg issued_at "$timestamp" \
      '
      {
        contract_version: $contract_version,
        event_type: $event_type,
        dispatch_mode: $dispatch_mode,
        dispatch_id: $dispatch_id,
        run_id: $run_id,
        issue_id: $issue_id,
        attempt: $attempt,
        workflow_mode: $workflow_mode,
        worker: {
          id: (if $worker_id == "" then null else $worker_id end),
          surface: (if $worker_surface == "" then null else $worker_surface end),
          model: (if $worker_model == "" then null else $worker_model end)
        },
        lease: {
          heartbeat_interval_seconds: $heartbeat_interval,
          ttl_seconds: $ttl
        },
        issued_at: $issued_at
      }')"
    ;;

  heartbeat)
    payload="$(jq -n -c \
      --arg contract_version "1.0" \
      --arg event_type "heartbeat" \
      --arg dispatch_id "$DISPATCH_ID" \
      --arg run_id "$RUN_ID" \
      --arg issue_id "$ISSUE_ID" \
      --arg phase "$PHASE" \
      --arg summary "$SUMMARY" \
      --arg worker_id "$WORKER_ID" \
      --arg worker_surface "$WORKER_SURFACE" \
      --argjson ttl "$TTL_SECONDS" \
      --arg sent_at "$timestamp" \
      '
      {
        contract_version: $contract_version,
        event_type: $event_type,
        dispatch_id: $dispatch_id,
        run_id: $run_id,
        issue_id: $issue_id,
        worker: {
          id: (if $worker_id == "" then null else $worker_id end),
          surface: (if $worker_surface == "" then null else $worker_surface end)
        },
        phase: (if $phase == "" then null else $phase end),
        summary: (if $summary == "" then null else $summary end),
        lease: {
          ttl_seconds: $ttl
        },
        sent_at: $sent_at
      }')"
    ;;

  complete)
    [ -n "$OUTCOME" ] || fail "--outcome is required for complete events"
    [ -n "$EXIT_CODE" ] || fail "--exit-code is required for complete events"
    [ -n "$RETRYABLE" ] || RETRYABLE="false"

    payload="$(jq -n -c \
      --arg contract_version "1.0" \
      --arg event_type "complete" \
      --arg dispatch_id "$DISPATCH_ID" \
      --arg run_id "$RUN_ID" \
      --arg issue_id "$ISSUE_ID" \
      --argjson attempt "${ATTEMPT:-1}" \
      --arg outcome "$OUTCOME" \
      --argjson exit_code "$EXIT_CODE" \
      --arg failure_category "$FAILURE_CATEGORY" \
      --argjson retryable "$RETRYABLE" \
      --arg result_path "$RESULT_PATH" \
      --arg completed_at "$timestamp" \
      '
      {
        contract_version: $contract_version,
        event_type: $event_type,
        dispatch_id: $dispatch_id,
        run_id: $run_id,
        issue_id: $issue_id,
        attempt: $attempt,
        outcome: $outcome,
        exit_code: $exit_code,
        failure_category: (if $failure_category == "" then null else $failure_category end),
        retryable: $retryable,
        result_path: (if $result_path == "" then null else $result_path end),
        completed_at: $completed_at
      }')"
    ;;
esac

if [ -n "$OUTPUT_PATH" ]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  printf '%s\n' "$payload" >> "$OUTPUT_PATH"
else
  printf '%s\n' "$payload"
fi
