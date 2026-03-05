# Cursor And Codex Mapping Matrix

This matrix defines the canonical one-to-one mapping from shared command contracts to Cursor and Codex adapters.

| Core Command Contract | Cursor Slash Command | Codex Skill | Core Reference |
| --- | --- | --- | --- |
| `create-project` | `/ralph/create-project` | `ralph-create-project` | `../../core/commands/create-project.md` |
| `populate-project` | `/ralph/populate-project` | `ralph-populate-project` | `../../core/commands/populate-project.md` |
| `generate-prd-from-project` | `/ralph/generate-prd-from-project` | `ralph-generate-prd-from-project` | `../../core/commands/generate-prd-from-project.md` |
| `audit-project` | `/ralph/audit-project` | `ralph-audit-project` | `../../core/commands/audit-project.md` |
| `ralph-run` | `/ralph/ralph-run` | `ralph-run` | `../../core/commands/ralph-run.md` |

## Mapping Contract Rules

- Each row is authoritative and must remain one-to-one.
- Surface naming may differ in format, but meaning must stay equivalent to the core command contract.
- Any row change requires synchronized updates in both `cursor/README.md` and `codex/README.md`.
