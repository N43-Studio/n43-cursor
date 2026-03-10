# Command Contract: `generate-prd-from-project`

## Intent

Generate a PRD artifact from the populated Ralph project state.

## Preconditions

- `populate-project` postconditions are satisfied.
- Required project data for PRD generation is complete.

## Postconditions

- PRD artifact is generated from canonical project state.
- PRD output references the originating Linear `Issue`.
- PRD carries issue metadata required for deterministic scheduling and cost planning:
  - `priority`
  - `status`
  - `labels`
  - `estimatedPoints`/`estimate`
  - optional `estimatedTokens` (recommended from `issue-metadata-rubric.md`)

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (generation rules come from core contracts).
- `WF-INV-003` Ordered transitions (phase 3 only after phase 2).
- `WF-INV-004` Traceability (PRD linked to `Issue`).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
