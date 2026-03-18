# {{PROJECT_NAME}} - Project Closeout

## Goal

Finalize the {{PROJECT_NAME}} project by verifying all deliverables, running final validations, and archiving project artifacts. This issue activates automatically when all other project issues reach a terminal state (Done or Canceled).

## Context

This is a dormant closeout issue seeded during project population. It remains in Backlog until the auto-promotion trigger fires. The trigger condition is: every non-closeout issue in the project has reached Done or Canceled status.

## Closeout Checklist

- [ ] All project issues are in a terminal state (Done / Canceled)
- [ ] Final validation suite passes (lint, typecheck, test, build)
- [ ] No unresolved blocking relationships remain
- [ ] Retrospective artifacts generated (if applicable)
- [ ] Calibration store updated with project actuals
- [ ] Project status set to Completed in Linear
- [ ] Branch cleanup: feature branches merged or deleted

## Implementation Notes

- Scope: Project-level housekeeping, no new feature work
- Files/components expected to change: none (validation and metadata only)
- Non-goals: introducing new functionality, refactoring existing code
- Edge cases to handle: partially canceled projects where some issues were Canceled intentionally

## Dependencies

- blockedBy: all other issues in the project (implicit; enforced by auto-promotion trigger)
- blocks: none

## Acceptance Criteria

- [ ] All non-closeout project issues confirmed terminal
- [ ] Final validation passes cleanly
- [ ] Project marked Completed in Linear
- [ ] Any retrospective or calibration data committed

## Validation

- lint: `pnpm lint`
- typecheck: `pnpm typecheck`
- test: `pnpm test`
- build: `pnpm build`

## Metadata Rationale

- priority: 4 (Low)
- estimate: 1
- estimatedTokens: ~2000
- confidence: high
- lowConfidence: false
- rubricFactors: deterministic closeout checklist, no design decisions

## Labels

- `Ralph`
- `Agent Generated`
