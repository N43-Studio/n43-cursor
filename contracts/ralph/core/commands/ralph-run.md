# Command Contract: `ralph-run`

## Intent

Execute deterministic Ralph issue iterations from `prd.json` after all prerequisite contract checks pass.

## Preconditions

- `audit-project` completed with a pass result.
- All required execution inputs are present and traceable.
- `scripts/ralph-run.sh` is the canonical runtime entrypoint.
- Per-issue invocation uses `../cli-issue-execution-contract.md`.
- Runnable issues satisfy readiness semantics (`Ralph` + `PRD Ready`, excluding `Human Required`).
- Runnable issues satisfy claim safety semantics with exactly one active owner at claim time when Linear sync is enabled.

## Postconditions

- Each selected issue is executed exactly once per iteration through the CLI issue execution contract.
- Execution result is recorded with status and associated Linear `Issue`.
- Output metadata is sufficient for parity checks across control surfaces.
- Each issue attempt appends a structured `run-log.jsonl` entry for retrospective/calibration consumers.
- Loop state is persisted every iteration for deterministic resume (`.cursor/ralph/<project>/loop-state.json` or explicit override path).
- Ambiguity requiring human input is recorded with structured assumptions and resumable revision context.
- Retry eligibility is explicit and deterministic (`retryable`, `retry_after_seconds`, `failure_category`).
- Stale running state is detected before resume; resume proceeds only when state is stale or explicitly non-running.
- `progress.txt` is canonical for run progress signaling; structured sidecars are optional and must not gate completion detection.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (execution respects core semantics).
- `WF-INV-003` Ordered transitions (phase 5 terminal action).
- `WF-INV-004` Traceability (result linked to `Issue`).
- `WF-INV-005` Validation gate (requires successful audit).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
- `WF-INV-008` Claim safety (single-owner claim lifecycle with stale recovery).

## Contract Artifacts

- CLI invocation and payload semantics: `../cli-issue-execution-contract.md`
- CLI result schema: `../schema/cli-issue-execution-result.schema.json`
