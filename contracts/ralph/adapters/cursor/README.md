# Cursor Adapter

This adapter maps Cursor command surfaces to Ralph core contracts.

## Scope

- Command-level bindings for Cursor workflows.
- Cursor-specific invocation metadata that references, but does not redefine, core contracts.

## Command Mapping

| Core Command Contract | Cursor Slash Command |
| --- | --- |
| `build` | `/ralph/build` |
| `create-project` | `/ralph/create-project` |
| `create-issue` | `/linear/create-issue` |
| `populate-project` | `/ralph/populate-project` |
| `generate-prd-from-project` | `/ralph/generate-prd-from-project` |
| `audit-project` | `/ralph/audit-project` |
| `ralph-run` | `/ralph/ralph-run` |

Core contract references are canonical in `../mapping.md`.
Result schema is canonical in `../../core/schema/normalized-result.schema.json`.

## Thin Adapter Constraints

- Translate only invocation wiring and contract I/O shape.
- Do not alter command sequencing or invariants from `../../core/linear-workflow.md`.
- Preserve canonical `workflow_mode` semantics without adding Cursor-only behavior.
- Keep Linear work item terminology as `Issue`.

## Prohibited Divergence Examples

- Adding a Cursor-only preflight phase before `populate-project`.
- Allowing `/ralph/ralph-run` when `audit-project` failed.

## Boundary

- If a mapping conflicts with core semantics, update core first, then update this adapter.
- No-drift enforcement rules are defined in `../no-drift-rules.md`.
- Cursor `/ralph/ralph-run` is a supported iterative runtime surface, parity-aligned with script and Codex entrypoints.

## Plan Mode Routing

- Cursor plan-mode entry points must follow `../../core/plan-mode-contract.md`.
- Planning behavior must route through `commands/implementation/plan-feature.md`.
- Execution requires explicit user approval checkpoint after plan summary.
