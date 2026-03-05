---
name: ralph-generate-prd-from-project
description: Codex wrapper for the Ralph generate-prd-from-project command contract. Use when producing a PRD from populated Ralph project state.
---

# Ralph Generate PRD Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/generate-prd-from-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `generate-prd-from-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.
