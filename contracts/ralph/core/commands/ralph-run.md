# Command Contract: `ralph-run`

## Intent

Execute the Ralph workflow outcome after all prerequisite contract checks pass.

## Preconditions

- `audit-project` completed with a pass result.
- All required execution inputs are present and traceable.
- Runnable issues satisfy readiness semantics (`Ralph` + `PRD Ready`, excluding `Human Required`).
- Runnable issues satisfy claim safety semantics with exactly one active owner at claim time.

## Postconditions

- Execution result is recorded with status and associated Linear `Issue`.
- Output metadata is sufficient for parity checks across control surfaces.
- Each issue attempt appends a structured `run-log.jsonl` entry for retrospective/calibration consumers.
- Ambiguity requiring human input is recorded with structured assumptions and resumable revision context.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (execution respects core semantics).
- `WF-INV-003` Ordered transitions (phase 5 terminal action).
- `WF-INV-004` Traceability (result linked to `Issue`).
- `WF-INV-005` Validation gate (requires successful audit).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
- `WF-INV-008` Claim safety (single-owner claim lifecycle with stale recovery).
