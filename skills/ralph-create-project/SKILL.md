---
name: ralph-create-project
description: "Linear PM skill: initialize a Ralph project workspace for a Linear Issue. Use when setting up a new project scaffold bound to a Linear Issue identifier."
---

# Ralph Create Project — Linear PM Skill

> **This is a Linear PM operation, not a Ralph execution operation.**
> It manages project scaffolding in Linear and the local workspace. It does not implement code, run tests, or advance the Ralph execution loop.

## Contract Wiring

- Command contract: `contracts/ralph/core/commands/create-project.md`
- Shared validations: `contracts/ralph/core/shared-validations.md`
- Result schema: `contracts/ralph/core/schema/normalized-result.schema.json`
- Surface mapping: `contracts/ralph/adapters/mapping.md`

## Wrapper Behavior

1. Validate `SV-001` through `SV-004` from shared validations.
2. Execute the `create-project` contract without adding surface-specific semantics.
3. Emit normalized output fields required by shared validations.

## Intent Boundary

- **Category**: Linear PM (administrative/setup).
- Owns only the Ralph `create-project` contract phase — initializing a project scaffold bound to a Linear Issue.
- Does **not** perform Ralph execution (`ralph-run`), code implementation, or test validation.
- For runtime execution of issues, use the `ralph-run` skill.
- For non-contract project/issue administration outside the Ralph pipeline, hand off to the `linear` skill group.
- Do not use for Linear PM triage/admin workflows.
