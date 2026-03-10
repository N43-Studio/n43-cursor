# Command Contract: `audit-project`

## Intent

Audit project artifacts for contract conformance before execution.

## Preconditions

- `generate-prd-from-project` postconditions are satisfied.
- Audit criteria from core contracts are available.

## Postconditions

- Audit result is explicitly pass/fail with actionable findings on failure.
- Successful audits certify readiness for `ralph-run`.
- Audit explicitly validates readiness semantics (`Ralph` + `PRD Ready`, excluding `Human Required`) and treats `Agent Generated` as provenance-only.
- Audit validates claim safety semantics (required claim labels, single-owner claims, stale-claim recovery conditions).
- Audit validates ambiguity handoff completeness for `Human Required` issues and revision resumability semantics.
- Audit validates metadata quality against `../issue-metadata-rubric.md`, including:
  - missing `priority` or `estimate`
  - missing metadata rationale
  - low-confidence metadata (`confidence < 0.60`)

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (audit evaluates against core contracts).
- `WF-INV-003` Ordered transitions (phase 4 only after phase 3).
- `WF-INV-005` Validation gate (`ralph-run` blocked unless audit passes).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
- `WF-INV-008` Claim safety (single-owner claim lifecycle with stale recovery).

## Contract Artifacts

- Metadata rubric: `../issue-metadata-rubric.md`
