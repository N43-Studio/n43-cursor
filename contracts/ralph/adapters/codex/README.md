# Codex Adapter

This adapter maps Codex skill surfaces to Ralph core contracts.

## Scope

- Skill-level bindings for Codex workflows.
- Codex-specific execution metadata that references, but does not redefine, core contracts.
- Intent boundaries are defined in `skill-boundary.md`.

## Command Mapping

| Core Command Contract | Codex Skill |
| --- | --- |
| `create-project` | `ralph-create-project` |
| `populate-project` | `ralph-populate-project` |
| `generate-prd-from-project` | `ralph-generate-prd-from-project` |
| `audit-project` | `ralph-audit-project` |
| `ralph-run` | `ralph-run` |

Core contract references are canonical in `../mapping.md`.
Result schema is canonical in `../../core/schema/normalized-result.schema.json`.

## Thin Adapter Constraints

- Translate only invocation wiring and contract I/O shape.
- Do not alter command sequencing or invariants from `../../core/linear-workflow.md`.
- Keep Linear work item terminology as `Issue`.

## Prohibited Divergence Examples

- Codex skill accepts a non-contract field not present in core command contract inputs.
- Codex uses non-canonical terminology for Linear work items in output summaries.

## Boundary

- If a mapping conflicts with core semantics, update core first, then update this adapter.
- No-drift enforcement rules are defined in `../no-drift-rules.md`.

## Plan Mode Routing

- Codex plan-mode entry points must follow `../../core/plan-mode-contract.md`.
- Planning behavior must route through `commands/implementation/plan-feature.md`.
- Execution requires explicit user approval checkpoint after plan summary.
