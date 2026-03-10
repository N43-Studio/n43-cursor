# Command Contract: `create-issue`

## Intent

Create exactly one implementation-ready Linear issue using readiness taxonomy and explicit approval before mutation.

## Preconditions

- Target Linear project is resolved unambiguously.
- Readiness taxonomy from `../readiness-taxonomy.md` is available.
- Draft issue structure satisfies PRD-ready template semantics.

## Postconditions

- Exactly one issue is created or zero (if approval withheld).
- Created issue includes deterministic implementation-ready structure.
- Labels and state follow readiness semantics (`Ralph`, `PRD Ready`, `Agent Generated` by default).
- Optional dependency links (`blockedBy`, `blocks`) are applied when provided.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (core semantics preserved).
- `WF-INV-004` Traceability (created issue is explicitly reported).
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).

## Contract Artifacts

- Readiness taxonomy: `../readiness-taxonomy.md`
- PRD-ready template: `templates/linear/prd-ready-issue.md`
