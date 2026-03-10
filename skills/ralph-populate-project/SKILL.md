---
name: ralph-populate-project
description: Codex wrapper for the Ralph populate-project command contract. Use when enriching an initialized Ralph project with Issue context.
---

# Ralph Populate Project Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/populate-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `populate-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.

## Intent Boundary

- Owns only the Ralph `populate-project` contract phase.
- Do not use for Linear PM triage/admin workflows.
- For non-contract project/issue administration, hand off to the `linear` skill group.
