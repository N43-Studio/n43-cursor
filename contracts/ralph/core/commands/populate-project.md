# Command Contract: `populate-project`

## Intent

Populate the initialized Ralph project with required issue context and working artifacts.

## Preconditions

- `create-project` postconditions are satisfied.
- Source context required for project population is available.

## Postconditions

- Project contains normalized inputs needed for PRD generation.
- Population outputs remain traceable to the originating Linear `Issue`.
- Generated automation-targeted issues are labeled with readiness semantics (`Ralph` + `PRD Ready`); `Agent Generated` is provenance metadata.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (outputs align to core contracts).
- `WF-INV-003` Ordered transitions (phase 2 only after phase 1).
- `WF-INV-004` Traceability (retains `Issue` binding).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
