# Core Contracts

`contracts/ralph/core/` contains tool-agnostic workflow contracts.

## What Belongs Here

- Canonical workflow model and lifecycle states.
- Canonical schema for workflow entities and fields.
- Cross-surface terminology and naming constraints.
- Invariants and validation rules that every adapter must satisfy.
- `linear-workflow.md` for sequencing and shared invariants only.
- `shared-validations.md` for cross-surface validation gates.
- `readiness-taxonomy.md` for readiness/provenance labeling policy and migration rules.
- `status-semantics.md` for canonical Linear status lifecycle mapping and review-loop behavior.
- `claim-protocol.md` for collision-safe parallel claim lifecycle, ownership, and stale-claim recovery.
- `dispatch-protocol.md` for standalone vs orchestrated dispatch ownership, lifecycle payloads, and state boundaries.
- `cli-issue-execution-contract.md` for canonical per-issue CLI invocation inputs/outputs and exit semantics.
- `issue-creation-delegation-contract.md` for delegated non-blocking issue-creation intent queue and worker semantics.
- `review-feedback-sweep-contract.md` for non-blocking reviewed-state feedback requeue semantics between iterations.
- `retrospective-contract.md` for deterministic post-run retrospective generation and reporting semantics.
- `plan-mode-contract.md` for cross-surface planning-mode routing and approval parity via `plan-feature`.
- `schema/*.schema.json` for canonical payload schema and required freshness hashes.
- `commands/*.md` for per-command contracts that reference workflow invariants.

## What Does Not Belong Here

- Cursor command syntax or command-specific wiring.
- Codex skill execution details or tool-call instructions.
- Any implementation detail that only one surface can consume.

Core contracts must be consumable by both Cursor and Codex without reinterpretation.
