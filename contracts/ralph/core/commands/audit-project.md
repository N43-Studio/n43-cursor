# Command Contract: `audit-project`

## Intent

Audit project artifacts for contract conformance before execution.

## Preconditions

- `generate-prd-from-project` postconditions are satisfied.
- Audit criteria from core contracts are available.

## Postconditions

- Audit result is explicitly pass/fail with actionable findings on failure.
- Successful audits certify readiness for `ralph-run`.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (audit evaluates against core contracts).
- `WF-INV-003` Ordered transitions (phase 4 only after phase 3).
- `WF-INV-005` Validation gate (`ralph-run` blocked unless audit passes).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
