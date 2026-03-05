---
name: ralph-create-project
description: Codex wrapper for the Ralph create-project command contract. Use when initializing a Ralph project for a Linear Issue.
---

# Ralph Create Project Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/create-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `create-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.
