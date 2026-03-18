---
name: ralph-audit-project
description: Codex wrapper for the Ralph audit-project command contract. Use when validating project artifacts before ralph-run.
---

# Ralph Audit Project Wrapper

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/audit-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `audit-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.

## Intent Boundary

- Owns only the Ralph `audit-project` contract phase.
- Do not use for Linear PM triage/admin workflows.
- For non-contract project/issue administration, hand off to the `linear` skill group.
