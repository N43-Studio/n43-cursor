# Command Contract: `build`

## Intent

Provide a single-entry setup wrapper that executes Ralph setup phases through audit without launching runtime execution.

## Preconditions

- Inputs required to resolve or create a target project are supplied (either `project` or `objective`).
- Core contracts for `create-project`, `populate-project`, `generate-prd-from-project`, and `audit-project` are available.
- Shared validation rules from `../shared-validations.md` are available.

## Phase Definitions

### Phase 1: `create-project`

| Aspect | Detail |
|---|---|
| Precondition | `objective` supplied, or `project` resolves to existing project |
| Postcondition | Project exists in Linear with `id`, `name`, `url` |
| Artifact | None (metadata captured in build state) |
| Skip condition | `project` already supplied and resolves |

### Phase 2: `populate-project`

| Aspect | Detail |
|---|---|
| Precondition | Phase 1 complete; project resolves with description + milestones |
| Postcondition | Issues created under the project per `populate-project.md` contract |
| Artifact | Issues in Linear |
| Skip condition | Never (always runs unless `stop_at` prevents) |

### Phase 3: `generate-prd-from-project`

| Aspect | Detail |
|---|---|
| Precondition | Phase 2 complete; project has issues |
| Postcondition | `prd.json` generated at configured output path |
| Artifact | `{output_path}` (default `.cursor/ralph/{project-slug}/prd.json`) |
| Skip condition | `stop_at=create` or `stop_at=populate` |

### Phase 4: `audit-project`

| Aspect | Detail |
|---|---|
| Precondition | Phase 3 complete; PRD artifact exists |
| Postcondition | Audit result with pass/fail findings |
| Artifact | Audit report (inline output) |
| Skip condition | `stop_at=create`, `stop_at=populate`, or `stop_at=generate-prd` |

## Build State

Build state is persisted at `.cursor/ralph/{project-slug}/build-state.json` after each phase transition.

Schema:

```json
{
  "goal": "<string>",
  "project_id": "<string|null>",
  "project_name": "<string|null>",
  "project_url": "<string|null>",
  "team": "<string>",
  "prd_path": "<string|null>",
  "phases": {
    "create": { "status": "<pending|running|complete|failed|skipped>", "completed_at": "<ISO8601|null>" },
    "populate": { "status": "<pending|running|complete|failed|skipped>", "completed_at": "<ISO8601|null>" },
    "generate_prd": { "status": "<pending|running|complete|failed|skipped>", "completed_at": "<ISO8601|null>" },
    "audit": { "status": "<pending|running|complete|failed|skipped>", "completed_at": "<ISO8601|null>" }
  }
}
```

Build state enables:

- **Resumption**: completed phases are not re-executed when `project` is supplied
- **Observability**: phase-by-phase progress is visible to external tooling
- **Failure recovery**: failed phase + prior state provide explicit resume point

## Error Handling Semantics

- Phase failures are fatal: execution stops at the first failed phase.
- Failure output includes: failed phase name, failure reason, resume command, and whether prior artifacts remain valid.
- Build state records the failed phase with `status=failed`.

## Stop-At Semantics

When `stop_at` is set, phases after the named phase are recorded with `status=skipped` in build state. Valid values: `create`, `populate`, `generate-prd`, `audit`.

## Dry Run Semantics

When `dry_run=true`, no phases execute. Output includes the resolved phase plan with expected inputs and artifact paths. All phases report `status=dry_run`.

## Postconditions

- The wrapper executes setup phases in canonical order:
  1. `create-project`
  2. `populate-project`
  3. `generate-prd-from-project`
  4. `audit-project`
- Phase execution preserves artifact defaults and paths defined by the underlying command contracts.
- Build state is written after each phase transition.
- Wrapper output includes phase-by-phase pass/fail status with actionable remediation when a phase fails.
- Wrapper stops after audit output and does not launch `ralph-run`.

## Workflow Invariant Links

- `WF-INV-001` Terminology (`Issue` only).
- `WF-INV-002` Canonical source (phase semantics come from core command contracts).
- `WF-INV-003` Ordered transitions (phases remain monotonic and deterministic).
- `WF-INV-004` Traceability (setup artifacts remain bound to originating `Issue` context).
- `WF-INV-005` Validation gate (audit remains required before `ralph-run`).
- `WF-INV-006` Deterministic semantics across Cursor and Codex.

## Contract Artifacts

- `create-project`: `create-project.md`
- `populate-project`: `populate-project.md`
- `generate-prd-from-project`: `generate-prd-from-project.md`
- `audit-project`: `audit-project.md`
- Workflow invariants: `../linear-workflow.md`
- Shared validations: `../shared-validations.md`
