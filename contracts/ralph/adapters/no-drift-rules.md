# Adapter No-Drift Rules

This contract defines non-negotiable anti-drift rules for Cursor and Codex adapters.

## Thin Adapter Requirements

Adapters may only:

- map canonical command contracts to surface-native invocation names
- translate contract-defined inputs/outputs without semantic changes
- add surface metadata only when it does not alter lifecycle meaning

Adapters must not:

- introduce net-new lifecycle phases or status semantics
- weaken required validation/ordering gates from core contracts
- fork canonical schemas or redefine field meanings

## One-to-One Mapping Rule

Each canonical command contract must map to exactly one Cursor entry and one Codex entry in `mapping.md`.

## Synchronized Change Rule

Any adapter mapping or behavior change requires synchronized updates to:

- `contracts/ralph/adapters/mapping.md`
- `contracts/ralph/adapters/cursor/README.md`
- `contracts/ralph/adapters/codex/README.md`

## Prohibited Divergence Examples

- Cursor allows execution before required audit, Codex blocks it.
- Codex renames core-required fields while Cursor uses canonical names.
- One adapter adds optional behavior that changes deterministic output semantics.

## Verification

Use `scripts/check-ralph-drift.sh` to enforce no-drift guardrails.
