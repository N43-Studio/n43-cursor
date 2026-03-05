# Command Contract: `create-project`

## Intent

Initialize a new Ralph project workspace for a single Linear `Issue`.

## Preconditions

- A valid Linear `Issue` identifier is supplied.
- Target project path or namespace is resolvable.

## Postconditions

- Project scaffold exists and is uniquely associated to the `Issue` identifier.
- Initialization metadata required by downstream commands is persisted.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-003` Ordered transitions (phase 1 entry point).
- `WF-INV-004` Traceability (project bound to `Issue`).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
