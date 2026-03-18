---
name: ralph-create-issue
description: "Linear PM skill: create exactly one implementation-ready Linear Issue with readiness taxonomy and approval gating. Use when adding a single issue to a Ralph project."
---

# Ralph Create Issue — Linear PM Skill

> **This is a Linear PM operation, not a Ralph execution operation.**
> It creates and labels issues in Linear with readiness semantics. It does not implement code, run tests, or advance the Ralph execution loop.

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/create-issue.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `create-issue` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.

## Intent Boundary

- **Category**: Linear PM (administrative/setup).
- Owns only the Ralph `create-issue` contract phase — creating exactly one implementation-ready issue with rubric-derived metadata.
- Does **not** perform Ralph execution (`ralph-run`), code implementation, or test validation.
- For runtime execution of issues, use the `ralph-run` skill.
- For non-contract project/issue administration outside the Ralph pipeline, hand off to the `linear` skill group.
- Do not use for Linear PM triage/admin workflows.
