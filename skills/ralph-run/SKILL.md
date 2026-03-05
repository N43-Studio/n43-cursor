---
name: ralph-run
description: Codex wrapper for the Ralph ralph-run command contract. Use when executing Ralph workflow after audit-project passes.
---

# Ralph Run Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/ralph-run.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-005` from shared validations.
2. Execute the `ralph-run` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.
