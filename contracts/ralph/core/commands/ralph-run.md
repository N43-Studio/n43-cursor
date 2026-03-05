# Command Contract: `ralph-run`

## Intent

Execute the Ralph workflow outcome after all prerequisite contract checks pass.

## Preconditions

- `audit-project` completed with a pass result.
- All required execution inputs are present and traceable.

## Postconditions

- Execution result is recorded with status and associated Linear `Issue`.
- Output metadata is sufficient for parity checks across control surfaces.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (execution respects core semantics).
- `WF-INV-003` Ordered transitions (phase 5 terminal action).
- `WF-INV-004` Traceability (result linked to `Issue`).
- `WF-INV-005` Validation gate (requires successful audit).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
