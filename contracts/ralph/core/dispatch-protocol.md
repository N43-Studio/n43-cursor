# Ralph Dispatch Protocol

## Intent

Define the machine-facing dispatch lifecycle Ralph uses to start, monitor, and finish exactly one issue execution attempt without re-deciding ownership boundaries for future parallel orchestration work.

This protocol is intentionally separate from:

- `commands/ralph-run.md`, which defines loop semantics and deterministic scheduling policy
- `cli-issue-execution-contract.md`, which defines the per-issue worker input/output JSON
- `claim-protocol.md`, which defines Linear-visible claim safety and status/owner transitions

## Orthogonal Modes

Ralph has two independent mode dimensions:

- `workflow_mode`: `independent` or `human-in-the-loop`
- `dispatch_mode`: `standalone` or `orchestrated`

`workflow_mode` controls how review/clarification is resolved. `dispatch_mode` controls who owns queueing, leases, heartbeats, and retry coordination. One mode must never be inferred from the other.

## Dispatch Modes

### `standalone`

`scripts/ralph-run.sh` is the dispatcher.

It owns:

- candidate selection from `prd.json`
- per-iteration ordering and retry decisions
- local run state (`loop-state.json`, `progress.txt`, optional `run-log.jsonl`)
- invocation of the CLI issue execution contract for one issue attempt at a time

No external orchestrator lease ledger is required in this mode. Local Ralph artifacts act as the dispatch record.

### `orchestrated`

An external orchestrator is the dispatcher.

It owns:

- queue membership and issue admission to workers
- dispatch identifiers and worker assignment
- lease acquisition, heartbeat expiry, and stale-worker recovery
- retry scheduling/backoff across workers
- aggregate run accounting across parallel workers

In this mode, `scripts/ralph-run.sh` must not become a competing source of truth for global queue or lease state. It may be reused only as:

- the reference implementation for deterministic selection semantics, or
- a worker-side wrapper that executes one dispatched issue while honoring the same core contracts

## Boundary Rules

- The canonical Linear lifecycle remains defined by `claim-protocol.md` and `status-semantics.md`.
- The canonical per-issue execution payload/result remains defined by `cli-issue-execution-contract.md`.
- Dispatch metadata must not change issue-level success/failure semantics.
- Orchestrator state must never replace Linear as the user-visible source of issue lifecycle truth.
- Standalone local artifacts must not be reinterpreted as required cross-worker coordination state.
- Orchestrated implementations must preserve the deterministic selection/routing policy from `commands/ralph-run.md` when they perform selection outside the script.

## State Ownership

### Linear-owned state

- issue identifier and title
- visible workflow status (`In Progress`, `Needs Review`, `Human Required`, `Done`, etc.)
- active owner (`assignee`/`delegate`)
- human-visible progress, review, stale-claim, and handoff comments
- readiness/compatibility labels that remain in use during migration

### Dispatch-storage state

- `dispatch_id`
- `run_id`
- attempt number
- worker identity and surface/model metadata
- lease TTL, next-heartbeat deadline, and stale-dispatch timers
- retry/backoff bookkeeping
- queue/admission bookkeeping
- pointers to worker result artifacts

In `standalone`, this storage lives in local Ralph artifacts. In `orchestrated`, it lives in orchestrator-managed storage outside Linear.

## Dispatch Lifecycle

1. Select
   - Dispatcher chooses a runnable issue using the deterministic policy from `commands/ralph-run.md`.
2. Claim
   - Dispatcher records a dispatch claim and assigns a worker.
   - Worker must still honor Linear claim safety before doing issue work.
3. Heartbeat
   - Active worker refreshes dispatch liveness until completion or explicit release.
4. Complete
   - Worker emits terminal dispatch completion with the same outcome semantics used by `cli-issue-execution-contract.md`.
5. Release / Requeue
   - Dispatcher clears the active lease and either records completion or schedules a deterministic retry/handoff path.

## Canonical Payload Shapes

Dispatch payloads are JSON objects. Field names are canonical even when transport differs.

### Claim Payload

```json
{
  "contract_version": "1.0",
  "event_type": "claim",
  "dispatch_mode": "standalone",
  "dispatch_id": "run-20260317-01:N43-476:attempt-1",
  "run_id": "run-20260317-01",
  "issue_id": "N43-476",
  "attempt": 1,
  "workflow_mode": "independent",
  "worker": {
    "id": "codex-worker-1",
    "surface": "codex",
    "model": "deep"
  },
  "selection_context": {
    "policy": "dependency_ready -> readiness_structural_or_label_migration -> status_gate -> priority -> estimate -> issueId",
    "priority": 1,
    "estimate": 5
  },
  "lease": {
    "heartbeat_interval_seconds": 300,
    "ttl_seconds": 900
  },
  "issued_at": "2026-03-17T12:00:00Z"
}
```

Required semantics:

- `dispatch_id` uniquely identifies one active attempt.
- `run_id` groups related dispatches.
- `attempt` is monotonic per issue within a run.
- `workflow_mode` is propagated unchanged into the worker execution payload.

### Heartbeat Payload

```json
{
  "contract_version": "1.0",
  "event_type": "heartbeat",
  "dispatch_id": "run-20260317-01:N43-476:attempt-1",
  "run_id": "run-20260317-01",
  "issue_id": "N43-476",
  "attempt": 1,
  "worker": {
    "id": "codex-worker-1",
    "surface": "codex"
  },
  "phase": "validation",
  "summary": "Running lint and workflow-mode regression checks",
  "lease": {
    "ttl_seconds": 900
  },
  "sent_at": "2026-03-17T12:05:00Z"
}
```

Required semantics:

- Heartbeats refresh lease liveness only; they do not imply success.
- Missing heartbeats allow stale-dispatch recovery according to dispatcher policy.
- Linear progress comments remain optional human-facing mirrors, not heartbeat storage.

### Complete Payload

```json
{
  "contract_version": "1.0",
  "event_type": "complete",
  "dispatch_id": "run-20260317-01:N43-476:attempt-1",
  "run_id": "run-20260317-01",
  "issue_id": "N43-476",
  "attempt": 1,
  "outcome": "success",
  "exit_code": 0,
  "failure_category": null,
  "retryable": false,
  "result_path": ".ralph/results/N43-476-iter-3-result.json",
  "validation_results": {
    "lint": "pass",
    "typecheck": "skipped",
    "test": "pass",
    "build": "skipped"
  },
  "completed_at": "2026-03-17T12:07:00Z"
}
```

Required semantics:

- `outcome`, `exit_code`, `failure_category`, and `retryable` must agree with the CLI issue execution result.
- `result_path` points at the source-of-truth worker result payload when file artifacts are used.
- Completion closes the active dispatch lease for that `dispatch_id`.

## Runtime Flag Reference

`scripts/ralph-run.sh` accepts these dispatch-related flags:

| Flag | Values | Default | Mode |
|------|--------|---------|------|
| `--dispatch-mode` | `standalone`, `orchestrated` | `standalone` | Both |
| `--dispatch-id` | string | *(none)* | Required in orchestrated |
| `--dispatch-run-id` | string | *(none)* | Required in orchestrated |
| `--dispatch-log` | file path | stdout (orchestrated) | Both |

`--dispatch-mode standalone` preserves all existing behavior. No dispatch-specific flags are required.

`--dispatch-mode orchestrated` activates single-issue executor mode:

- `--dispatch-id` and `--dispatch-run-id` become required
- `--dispatch-log` optionally directs dispatch event output to a file (defaults to stdout)

Environment variables set during agent invocation in orchestrated mode:

| Variable | Value |
|----------|-------|
| `RALPH_DISPATCH_MODE` | `orchestrated` |
| `RALPH_DISPATCH_ID` | value of `--dispatch-id` |
| `RALPH_WORKFLOW_MODE` | value of `--workflow-mode` |

`scripts/emit-dispatch-event.sh` is a standalone helper for producing canonical dispatch payloads outside of `ralph-run.sh`. It accepts `--event claim|heartbeat|complete` with the same field names documented in the Canonical Payload Shapes section.

## Orchestrated Mode Restrictions

When `dispatch_mode=orchestrated`:

1. **No candidate selection.** The PRD must contain exactly one pending issue. The script does not run `next_issue()` scheduling logic; the orchestrator is responsible for pre-selecting and dispatching the issue.

2. **No loop-state management.** `loop-state.json` is not written or read. The orchestrator owns run-level state across workers. `--resume` has no effect.

3. **No post-loop processing.** Retrospective generation, calibration updates, issue-intent processing, review-feedback sweeps, and retrospective-improvement pipelines are skipped. The orchestrator coordinates these across the aggregate run.

4. **No retry coordination.** The script executes exactly one attempt. Retry/backoff decisions belong to the orchestrator based on the `complete` event payload.

5. **Single iteration ceiling.** `--max` is ignored; the script always runs exactly one iteration.

6. **Dispatch lifecycle events are emitted.** `claim` before execution, `heartbeat` during execution, and `complete` after execution are written to `--dispatch-log` (or stdout). These events follow the Canonical Payload Shapes defined above.

7. **PRD mutation on success.** The script still marks the issue as `passes: true` in the PRD on success. The orchestrator should treat the PRD as the worker's local artifact, not shared global state.

8. **Model routing is not applied.** Per-issue model routing is an orchestrator-level concern in orchestrated mode. The script uses the default `--agent-cmd`.

## Migration from Standalone to Orchestrated

### Incremental adoption path

1. **Start with standalone.** Existing `ralph-run.sh` invocations continue unchanged. The implicit dispatch mode is `standalone`.

2. **Add `--dispatch-mode standalone` explicitly.** This is a no-op but makes the dispatch mode visible in logs and loop-state.

3. **Build orchestrator dispatch layer.** The orchestrator selects issues, assigns dispatch IDs, and calls `ralph-run.sh --dispatch-mode orchestrated --dispatch-id <id> --dispatch-run-id <id> --prd <single-issue-prd>` per worker.

4. **Consume dispatch events.** The orchestrator reads `claim`, `heartbeat`, and `complete` events from `--dispatch-log` to drive retry, heartbeat monitoring, and aggregate accounting.

5. **Preserve contract parity.** The per-issue CLI execution contract (`cli-issue-execution-contract.md`), claim protocol (`claim-protocol.md`), and status semantics (`status-semantics.md`) are unchanged across modes. Only dispatch ownership moves.

### What the orchestrator replaces

| Standalone responsibility | Orchestrated owner |
|--------------------------|-------------------|
| `next_issue()` candidate selection | Orchestrator admission logic |
| `loop-state.json` run tracking | Orchestrator run ledger |
| Retry/escalation decisions | Orchestrator retry policy |
| Review-feedback sweep | Orchestrator-level sweep across workers |
| Retrospective generation | Orchestrator post-run pipeline |
| Calibration updates | Orchestrator post-run pipeline |
| Issue-intent processing | Orchestrator post-run pipeline |
| Model routing | Orchestrator pre-dispatch routing |

### What remains identical

- Per-issue agent invocation contract (input/output JSON)
- `claim-protocol.md` Linear claim safety
- Validation expectations and result schema
- PRD issue shape and `passes` semantics
- `progress.txt` append-only markers

## Compatibility Rules

- Existing standalone `scripts/ralph-run.sh` behavior implies `dispatch_mode=standalone` even before an explicit flag is added.
- Future orchestrated implementations may add transport- or storage-specific fields, but they must not rename or redefine the canonical fields above.
- Any future CLI/runtime flag for dispatch mode must default to `standalone` unless explicitly overridden.
- `dispatch_mode` and `workflow_mode` are orthogonal. All four combinations are valid: standalone+independent, standalone+human-in-the-loop, orchestrated+independent, orchestrated+human-in-the-loop.
