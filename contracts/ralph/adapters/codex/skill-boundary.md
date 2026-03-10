# Codex Skill Boundary Contract

This document defines intent routing boundaries between Linear project-management skills and Ralph execution skills.

## Skill Groups

- Linear PM skill group:
  - `linear` (workspace skill outside this repo)
  - Owns project/issue CRUD, triage, metadata curation, planning administration.
- Ralph execution skill group:
  - `ralph-create-project`
  - `ralph-populate-project`
  - `ralph-generate-prd-from-project`
  - `ralph-audit-project`
  - `ralph-run`
  - Owns Ralph contract phases and deterministic execution behavior.

## Intent Routing Matrix

| User Intent | Route |
| --- | --- |
| Create/update Linear projects, milestones, labels, or non-Ralph issue metadata | `linear` skill group |
| Create dependency-aware issue sets as part of Ralph contract workflow | `ralph-populate-project` |
| Generate PRD from Ralph project issues | `ralph-generate-prd-from-project` |
| Audit Ralph readiness semantics before execution | `ralph-audit-project` |
| Execute deterministic Ralph iterations | `ralph-run` |

## Handoff Rules

- Linear PM -> Ralph:
  - Once project/issue structure is ready, hand off to `ralph-create-project`/`ralph-populate-project` pipeline.
- Ralph -> Linear PM:
  - For non-contract PM tasks (manual triage, metadata tuning, backlog re-shaping), hand back to `linear`.

## Prohibited Overlap

- Ralph wrappers must not perform generic PM triage/administration.
- Linear PM skill must not redefine Ralph runtime semantics.
- Shared contract behavior remains canonical under `contracts/ralph/core/`.
