# Retrospective Contract

## Intent

Generate a deterministic post-run retrospective from `run-log.jsonl` and `prd.json` after iteration loop completion and before final run completion reporting.

## Inputs

- `run_log_path`: append-only JSONL run log.
- `prd_path`: PRD source used for issue execution.
- `output_path`: target `retrospective.json` file.
- Optional trace fields: `run_id`, `repo_root`.

## Output Artifact

`retrospective.json` must contain:

- `runSummary`
- `estimationAccuracy`
- `failurePatterns`
- `scopingObservations`
- `workflowFriction`
- `proposedImprovements`

The generator command must also emit a compact JSON summary on stdout for orchestration reporting.

## Non-Blocking Semantics

- Retrospective failures must not halt unrelated completion processing.
- Failure context is captured in run output and loop-state summary.
- If run-log is unavailable/disabled, generator should still produce deterministic empty or minimal analysis output.

## Reporting Semantics

`/ralph/run` must emit:

- `RUN_RETROSPECTIVE` marker before `RUN_COMPLETE`.
- Retrospective summary fields in `RUN_COMPLETE` and loop-state (`retrospective`).
