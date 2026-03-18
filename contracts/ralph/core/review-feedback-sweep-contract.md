# Review Feedback Sweep Contract

## Intent

Provide a deterministic, non-blocking mechanism for `/ralph/run` to detect human review feedback (`Reviewed`/`Needs Review`) and requeue affected issues between iterations.

This contract applies to the asynchronous review path used by `independent` workflow mode. `human-in-the-loop` mode resolves intermediate review inside the active execution cycle and does not require this sweep for in-loop clarification.

## Inputs

Sweep implementations must accept:

- `events_path`: JSONL stream of feedback events.
- `state_path`: sweep cursor/state file.
- `statuses`: comma-separated status allowlist (default `Reviewed,Needs Review`).
- `run_id`: current run identifier.
- `window_start`, `window_end`: ISO-8601 run window bounds.

## Feedback Event Shape

Each JSONL event should include:

- `issue_id` (or `issueId`/`identifier`): target issue identifier.
- `source_status` (or `status`/`current_status`): status at feedback time.
- Requeue signal via either:
  - `requires_rework = true`, or
  - `feedback_type`/`action`/`review_decision` in:
    - `requeue`
    - `reopen`
    - `changes_requested`
    - `revision_requested`
    - `needs_changes`

Invalid lines must not fail orchestration; they are counted and ignored.

## Output Contract

Sweep command returns a single JSON object:

```json
{
  "processed_events": 0,
  "matched_status_events": 0,
  "ignored_events": 0,
  "invalid_events": 0,
  "requeue_issue_ids": [],
  "previous_index": 0,
  "next_index": 0
}
```

Required semantics:

- `processed_events`: new events evaluated this sweep.
- `requeue_issue_ids`: unique issue IDs selected for requeue.
- `next_index`: cursor value persisted for next sweep.

## Orchestrator Semantics

When `/ralph/run` applies sweep output:

- Requeued issues in `prd.json` are forced to `passes=false`.
- Requeued issues are removed from local blocked-issue cache.
- Sweep does not block unrelated runnable issues.
- Failures in sweep command are tracked and reported, but must not halt run execution.

## Observability

`/ralph/run` must emit:

- `RUN_FEEDBACK_SWEEP` per sweep.
- `RUN_FEEDBACK_REQUEUE` per requeued issue.
- Feedback summary fields in `RUN_COMPLETE` and loop-state (`review_feedback`).
