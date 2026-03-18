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

## Improvement Pipeline Semantics

- Retrospective improvements with severity `critical` or `major` may be converted into delegated issue-creation intents.
- Generated intents should target the source Linear project when available.
- Dedup must be deterministic (for example, `retrospectiveSourceHash`-derived keys).
- `minor` improvements should remain informational by default (no auto-created issues).

## Calibration Semantics

- Retrospective data should be rich enough for deterministic calibration updates.
- Calibration updaters may append to a persistent `.cursor/ralph/calibration.json` store after retrospective generation.
- Calibration updates must be non-blocking for overall run completion.
