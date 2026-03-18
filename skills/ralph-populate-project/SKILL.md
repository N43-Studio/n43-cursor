---
name: ralph-populate-project
description: "Linear PM skill: populate an initialized Ralph project with implementation-ready issues derived from project milestones. Use when enriching a project with issue context."
---

# Ralph Populate Project — Linear PM Skill

> **This is a Linear PM operation, not a Ralph execution operation.**
> It populates a Linear project with issues, labels, metadata, and dependency links. It does not implement code, run tests, or advance the Ralph execution loop.

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

- **Category**: Linear PM (administrative/setup).
- Owns only the Ralph `populate-project` contract phase — generating issues from project milestones with rubric-derived metadata and readiness labels.
- Does **not** perform Ralph execution (`ralph-run`), code implementation, or test validation.
- For runtime execution of issues, use the `ralph-run` skill.
- For non-contract project/issue administration outside the Ralph pipeline, hand off to the `linear` skill group.
- Do not use for Linear PM triage/admin workflows.
