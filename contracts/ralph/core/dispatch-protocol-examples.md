# Dispatch Protocol — Worked Examples

Companion to `contracts/ralph/core/dispatch-protocol.md`. Each example traces the full dispatch lifecycle for a single issue attempt.

## Standalone Dispatch Lifecycle

### Scenario: Successful issue execution

`ralph-run.sh` selects `N43-476` from a multi-issue PRD and executes it in one attempt.

**1. Select**

`ralph-run.sh` runs `next_issue()` against `prd.json`. The deterministic scheduling policy selects `N43-476` based on dependency readiness, structural readiness, status gate, priority, and estimate.

```
RUN_SCHEDULE_DECISION timestamp=2026-03-18T10:00:00Z iteration=3 selected=N43-476 pending_candidates=4 runnable_candidates=2
```

**2. Claim**

In standalone mode, the claim is implicit. The script begins execution of the per-issue CLI contract. No explicit dispatch claim event is emitted — the `RUN_ITERATION` marker serves as the dispatch record.

Linear claim safety is still honored: the agent must respect `claim-protocol.md` before modifying the issue.

**3. Heartbeat**

The script writes `loop-state.json` periodically with `last_heartbeat_epoch` updated. No separate heartbeat events are emitted in standalone mode.

```json
{
  "status": "running",
  "last_heartbeat_epoch": 1742295660,
  "counters": { "iterations_executed": 3 }
}
```

**4. Complete**

The agent writes a result payload to `.ralph/results/N43-476-iter-3-result.json`:

```json
{
  "contract_version": "1.0",
  "issue_id": "N43-476",
  "iteration": 3,
  "outcome": "success",
  "exit_code": 0,
  "validation_results": { "lint": "pass", "typecheck": "pass", "test": "pass", "build": "skipped" },
  "artifacts": { "commit_hash": "abc1234", "files_changed": ["scripts/ralph-run.sh"] }
}
```

```
RUN_ITERATION timestamp=2026-03-18T10:07:00Z iteration=3 issue=N43-476 outcome=success
```

**5. Release**

The script marks `N43-476` as `passes: true` in the PRD and continues to the next iteration. No explicit release event — the loop iteration boundary is the release.

---

### Scenario: Failure with retry and eventual escalation

`N43-480` fails on the first attempt, retries at a higher tier, and escalates to human review.

**Iteration 1**: `N43-480` selected, tier=low, outcome=failure (validation failures).

```
RUN_ITERATION timestamp=2026-03-18T10:10:00Z iteration=4 issue=N43-480 outcome=failure tier=low
RUN_MODEL_ESCALATION timestamp=2026-03-18T10:10:01Z iteration=4 issue=N43-480 tier=low action=retry_with_escalation failure_count=1
```

**Iteration 2**: `N43-480` re-selected, tier=medium, outcome=failure.

```
RUN_ITERATION timestamp=2026-03-18T10:25:00Z iteration=5 issue=N43-480 outcome=failure tier=medium
RUN_MODEL_ESCALATION timestamp=2026-03-18T10:25:01Z iteration=5 issue=N43-480 tier=medium action=retry_with_escalation failure_count=2
```

**Iteration 3**: `N43-480` re-selected, tier=high, outcome=failure.

```
RUN_ITERATION timestamp=2026-03-18T10:40:00Z iteration=6 issue=N43-480 outcome=failure tier=high
RUN_MODEL_ESCALATION timestamp=2026-03-18T10:40:01Z iteration=6 issue=N43-480 tier=high action=highest_tier_failed_human_required failure_count=3 escalate_to_human=true
```

`N43-480` is added to the blocked list. The assumptions log records the handoff context. Future iterations skip `N43-480`.

---

## Orchestrated Dispatch Lifecycle

### Scenario: Successful single-issue execution

An external orchestrator dispatches `N43-476` to a worker.

**1. Orchestrator selects and prepares**

The orchestrator runs its own selection logic (preserving deterministic policy parity), creates a single-issue PRD, and assigns a dispatch ID.

**2. Worker invocation**

```bash
scripts/ralph-run.sh \
  --prd /tmp/dispatch/N43-476-prd.json \
  --dispatch-mode orchestrated \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --dispatch-run-id "run-20260318-01" \
  --dispatch-log /tmp/dispatch/events.jsonl \
  --agent-cmd scripts/configured-issue-agent.sh
```

**3. Claim event emitted**

Written to `/tmp/dispatch/events.jsonl`:

```json
{
  "contract_version": "1.0",
  "event_type": "claim",
  "dispatch_mode": "orchestrated",
  "dispatch_id": "run-20260318-01:N43-476:attempt-1",
  "run_id": "run-20260318-01",
  "timestamp": "2026-03-18T10:00:00Z",
  "issue_id": "N43-476",
  "attempt": 1,
  "workflow_mode": "independent"
}
```

**4. Heartbeat event emitted**

```json
{
  "contract_version": "1.0",
  "event_type": "heartbeat",
  "dispatch_mode": "orchestrated",
  "dispatch_id": "run-20260318-01:N43-476:attempt-1",
  "run_id": "run-20260318-01",
  "timestamp": "2026-03-18T10:00:01Z",
  "issue_id": "N43-476",
  "phase": "execution",
  "summary": "Starting agent execution"
}
```

**5. Agent executes**

The agent writes its result to `.ralph/results/N43-476-iter-1-result.json`. The script validates the result contract.

**6. Complete event emitted**

```json
{
  "contract_version": "1.0",
  "event_type": "complete",
  "dispatch_mode": "orchestrated",
  "dispatch_id": "run-20260318-01:N43-476:attempt-1",
  "run_id": "run-20260318-01",
  "timestamp": "2026-03-18T10:07:00Z",
  "issue_id": "N43-476",
  "attempt": 1,
  "outcome": "success",
  "exit_code": 0,
  "failure_category": null,
  "retryable": false,
  "result_path": ".ralph/results/N43-476-iter-1-result.json"
}
```

**7. Worker exits**

The script marks the issue as `passes: true` in the single-issue PRD and exits with code 0. The orchestrator reads the `complete` event and updates its run ledger.

```
RUN_COMPLETE timestamp=2026-03-18T10:07:01Z iterations=1 completed=1 pending=0 stop_reason=dispatch_single_issue dispatch_mode=orchestrated
```

---

### Scenario: Failure in orchestrated mode

`N43-480` fails in orchestrated mode. The worker does not retry — the orchestrator owns retry decisions.

**Complete event (failure):**

```json
{
  "contract_version": "1.0",
  "event_type": "complete",
  "dispatch_mode": "orchestrated",
  "dispatch_id": "run-20260318-01:N43-480:attempt-1",
  "run_id": "run-20260318-01",
  "timestamp": "2026-03-18T10:12:00Z",
  "issue_id": "N43-480",
  "attempt": 1,
  "outcome": "failure",
  "exit_code": 20,
  "failure_category": "validation_failure",
  "retryable": true,
  "result_path": ".ralph/results/N43-480-iter-1-result.json"
}
```

The worker exits with code 4. The orchestrator reads `retryable: true` and may schedule `attempt-2` with updated dispatch ID `run-20260318-01:N43-480:attempt-2`.

---

## Common Failure Scenarios and Recovery

### Stale heartbeat in standalone mode

The `loop-state.json` shows `status: "running"` but `last_heartbeat_epoch` is older than `stale_after_seconds`. A new run with `--resume true` detects the stale state, sets `STALE_RESUME_DETECTED=true`, and continues from the last known counters.

### Worker crash in orchestrated mode

The orchestrator monitors heartbeat events. If no heartbeat or complete event arrives within the lease TTL, the orchestrator considers the dispatch stale and may:

1. Re-dispatch the same issue to a new worker with an incremented attempt number
2. Record the stale dispatch in its ledger for observability
3. The abandoned worker's partial state is ignored — only `complete` events close dispatch leases

### PRD mismatch in orchestrated mode

If the single-issue PRD has zero pending issues (all already marked `passes: true`), the script fails immediately:

```
ERROR: orchestrated mode: no pending issues in PRD
```

If the PRD has more than one pending issue, the script also fails:

```
ERROR: orchestrated mode: expected exactly 1 pending issue, found 3
```

The orchestrator must provide a PRD with exactly one non-completed issue.

### Missing dispatch flags

If `--dispatch-mode orchestrated` is set without `--dispatch-id` or `--dispatch-run-id`:

```
ERROR: --dispatch-id is required in orchestrated mode
ERROR: --dispatch-run-id is required in orchestrated mode
```

### Network/tool failure during execution

Same as standalone: the agent writes a synthetic failure result payload if it crashes before writing output. The `complete` event reflects this with `failure_category: "tool_contract_violation"` and `retryable: false`. The orchestrator should inspect the result payload before scheduling a retry.

## Using emit-dispatch-event.sh Standalone

The helper script can produce dispatch events independently of `ralph-run.sh`, useful for orchestrator integrations or testing.

```bash
# Emit a claim event to a file
scripts/emit-dispatch-event.sh \
  --event claim \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --run-id "run-20260318-01" \
  --issue-id "N43-476" \
  --attempt 1 \
  --worker-id "codex-worker-1" \
  --worker-surface "codex" \
  --worker-model "deep" \
  --output /tmp/dispatch-events.jsonl

# Emit a heartbeat to stdout
scripts/emit-dispatch-event.sh \
  --event heartbeat \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --run-id "run-20260318-01" \
  --issue-id "N43-476" \
  --phase "validation" \
  --summary "Running lint checks"

# Emit a complete event
scripts/emit-dispatch-event.sh \
  --event complete \
  --dispatch-id "run-20260318-01:N43-476:attempt-1" \
  --run-id "run-20260318-01" \
  --issue-id "N43-476" \
  --outcome "success" \
  --exit-code 0 \
  --result-path ".ralph/results/N43-476-iter-1-result.json" \
  --output /tmp/dispatch-events.jsonl
```
