---
name: ralph-generate-prd-from-project
description: "Linear PM skill: generate a PRD artifact from populated Ralph project state. Use when producing the PRD that bridges Linear PM setup and Ralph execution."
---

# Ralph Generate PRD — Linear PM Skill

> **This is a Linear PM operation, not a Ralph execution operation.**
> It generates a PRD artifact from Linear project state. It does not implement code, run tests, or advance the Ralph execution loop.

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/generate-prd-from-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `generate-prd-from-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.

## Intent Boundary

- **Category**: Linear PM (administrative/setup).
- Owns only the Ralph `generate-prd-from-project` contract phase — producing a PRD artifact from canonical project state with issue metadata for scheduling.
- Does **not** perform Ralph execution (`ralph-run`), code implementation, or test validation.
- The PRD artifact this skill produces is the **handoff point** from Linear PM to Ralph execution.
- For runtime execution of issues, use the `ralph-run` skill.
- For non-contract project/issue administration outside the Ralph pipeline, hand off to the `linear` skill group.
- Do not use for Linear PM triage/admin workflows.
