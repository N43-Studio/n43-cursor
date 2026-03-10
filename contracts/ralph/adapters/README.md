# Adapter Contracts

`contracts/ralph/adapters/` contains surface-specific mappings from each control surface to `contracts/ralph/core/`.

## Adapter Responsibilities

- Translate core contracts into surface-native controls.
- Preserve core meaning exactly (no semantic drift).
- Keep terminology aligned with core (`Issue` for Linear work items).
- Keep one-to-one mappings between command contracts and each control surface.

## Adapter Constraints

- Adapters must not define new canonical semantics.
- Adapters must not fork or shadow core schema definitions.
- Adapter-specific metadata is allowed only if it does not alter core intent.

## Thin Adapter Rule

Adapters are translation layers only. They may:

- Translate contract-defined input/output fields to surface-native invocation shapes.
- Wire invocation names (Cursor slash command path, Codex skill id/path).

Adapters may not:

- Add net-new states, lifecycle steps, or command meaning.
- Change required fields or invariants defined in core contracts.
- Rename contract concepts in a way that changes semantics.

## No-Drift Rules

- A command contract must map to exactly one Cursor command and exactly one Codex skill.
- Adapter wording must preserve core semantics verbatim for required behavior.
- If one adapter changes mapping semantics, the other adapter must be updated in the same change set.

## Prohibited Divergence Examples

- Cursor adapter allows `ralph-run` without `audit-project` pass, while Codex blocks it.
- Codex adapter calls Linear work items with non-canonical terminology while Cursor uses `Issue`.
- Cursor adapter adds an optional phase not present in `core/linear-workflow.md`.

See `mapping.md` for the canonical one-to-one matrix.
See `no-drift-rules.md` for enforceable anti-drift constraints.
See `smoke-run.md` for the parity verification record.
