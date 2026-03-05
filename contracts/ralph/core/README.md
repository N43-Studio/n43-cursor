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
- `claim-protocol.md` for collision-safe parallel claim lifecycle, ownership, and stale-claim recovery.
- `schema/*.schema.json` for canonical payload schema and required freshness hashes.
- `commands/*.md` for per-command contracts that reference workflow invariants.

## What Does Not Belong Here

- Cursor command syntax or command-specific wiring.
- Codex skill execution details or tool-call instructions.
- Any implementation detail that only one surface can consume.

Core contracts must be consumable by both Cursor and Codex without reinterpretation.
