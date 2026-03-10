# Linear Workflow Contract

This contract defines Ralph workflow sequencing and invariants only.

## Sequencing

Workflow phases are ordered and monotonic:

1. `create-project`
2. `populate-project`
3. `generate-prd-from-project`
4. `audit-project`
5. `ralph-run`

No command may claim completion for a later phase unless all earlier phases satisfy their postconditions.

## Scope Boundary

This file intentionally contains sequencing and workflow invariants only.

Command-specific input/output contracts are owned by `contracts/ralph/core/commands/*.md` and must not be duplicated here.

## Workflow Invariants

- `WF-INV-001` Terminology: Linear work items are always called `Issue`.
- `WF-INV-002` Canonical source: core contracts are the source of truth; adapters only map.
- `WF-INV-003` Ordered transitions: command flow must follow sequencing without skipping phases.
- `WF-INV-004` Traceability: every run is attributable to a Linear `Issue` identifier.
- `WF-INV-005` Validation gate: `audit-project` must be successful before `ralph-run`.
- `WF-INV-006` Deterministic semantics: Cursor and Codex mappings must preserve identical outcomes for the same contract inputs.
- `WF-INV-007` Readiness semantics: automation eligibility is based on readiness labels (`Ralph` + `PRD Ready`) and exclusion labels (`Human Required`), not provenance labels.
- `WF-INV-008` Claim safety: each runnable issue must have single-owner claim transitions (`Ralph Queue` -> `Ralph Claimed` -> terminal), with stale-claim recovery before reclaim.
- `WF-INV-009` Status semantics: Linear status behavior must follow `status-semantics.md`, including deterministic review-cycle requeue rules.
