# Command Contract: `ralph-run`

## Intent

Execute deterministic Ralph issue iterations from `prd.json` after all prerequisite contract checks pass.

## Preconditions

- `audit-project` completed with a pass result.
- All required execution inputs are present and traceable.
- `scripts/ralph-run.sh` is the canonical runtime entrypoint.
- Per-issue invocation uses `../cli-issue-execution-contract.md`.
- Delegated issue creation semantics use `../issue-creation-delegation-contract.md`.
- Reviewed-state feedback sweep semantics use `../review-feedback-sweep-contract.md`.
- Post-run retrospective semantics use `../retrospective-contract.md`.
- Status gating semantics follow `../status-semantics.md`.
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
- Delegated issue-creation intents are handled via queue/worker flow and must not block per-iteration issue execution.
- Reviewed-state feedback sweep may requeue issues between iterations and must not block unrelated runnable issues.
- Post-run retrospective generation must execute before run completion reporting and remain non-blocking on failure.
- Critical/major retrospective improvements may enqueue delegated issue-creation intents using deterministic dedup keys before worker processing.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (execution respects core semantics).
- `WF-INV-003` Ordered transitions (phase 5 terminal action).
- `WF-INV-004` Traceability (result linked to `Issue`).
- `WF-INV-005` Validation gate (requires successful audit).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
- `WF-INV-008` Claim safety (single-owner claim lifecycle with stale recovery).
- `WF-INV-009` Status semantics (deterministic status lifecycle and review requeue behavior).

## Contract Artifacts

- CLI invocation and payload semantics: `../cli-issue-execution-contract.md`
- CLI result schema: `../schema/cli-issue-execution-result.schema.json`
- Delegated issue creation: `../issue-creation-delegation-contract.md`
- Review feedback sweep: `../review-feedback-sweep-contract.md`
- Retrospective generation: `../retrospective-contract.md`
