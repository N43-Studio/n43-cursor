# Command Contract: `populate-project`

## Intent

Populate the initialized Ralph project with required issue context and working artifacts.

## Preconditions

- `create-project` postconditions are satisfied.
- Source context required for project population is available.
- Metadata rubric from `../issue-metadata-rubric.md` is available.
- Stage model strategy from `../stage-model-strategy.md` is available.

## Postconditions

- Project contains normalized inputs needed for PRD generation.
- Population outputs remain traceable to the originating Linear `Issue`.
- Generated automation-targeted issues are labeled with readiness semantics (`Ralph` + `PRD Ready`); `Agent Generated` is provenance metadata.
- Deprecated claim labels (`Ralph Queue`, `Ralph Claimed`, `Ralph Completed`) are compatibility-only and must not be required for populated issues.
- When decomposing superseded umbrella issues, follow `issue-decomposition-safety.md`:
  - create replacements first
  - avoid parent/sub-issue hierarchy to the superseded umbrella
  - prefer dependency/related links (`blockedBy`, `blocks`, `related`)
  - if using cancel strategy: unparent all existing children before canceling (Linear cascades cancel to children)
  - if using done strategy: mark parent Done (no cascade risk)
  - terminalize superseded parent only after replacements are confirmed runnable
  - use `scripts/safe-decompose-issue.sh` for automated decomposition with `--dry-run` preview
- Each generated issue includes deterministic metadata from the rubric:
  - `priority`
  - `estimate`
  - `estimatedTokens`
  - `confidence` + `lowConfidence`
  - concise metadata rationale
- A dormant **Project Closeout** issue is seeded unconditionally (unless one already exists):
  - Title: `<Project Name> - Project Closeout`
  - Priority: 4 (Low), Estimate: 1
  - Labels: `Ralph`, `Agent Generated` (no `PRD Ready` until promoted)
  - Status: Backlog (dormant)
  - Template source: `templates/project-closeout/closeout-issue-template.md`
- Closeout auto-promotion invariant: when every non-closeout issue in the project reaches a terminal state (`Done` or `Canceled`), the closeout issue is promoted to `Todo` and labeled `PRD Ready`.
- Duplicate guard: if a project issue with title suffix `- Project Closeout` already exists, seeding is skipped.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (outputs align to core contracts).
- `WF-INV-003` Ordered transitions (phase 2 only after phase 1).
- `WF-INV-004` Traceability (retains `Issue` binding).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.
- `WF-INV-007` Readiness semantics (labels drive automation eligibility).
- `WF-INV-008` Claim safety (population must not encode readiness assumptions into deprecated claim labels).

## Contract Artifacts

- Metadata rubric: `../issue-metadata-rubric.md`
- Stage model strategy: `../stage-model-strategy.md`
- Closeout issue template: `templates/project-closeout/closeout-issue-template.md`
- Decomposition safety: `../issue-decomposition-safety.md`
