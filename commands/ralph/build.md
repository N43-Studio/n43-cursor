> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Single-entry orchestration must deterministically execute four contract phases and preserve artifact semantics -->

# Build Ralph Setup (Create -> Populate -> PRD -> Audit)

Run a single command wrapper that chains Ralph setup phases through audit and then stops.

`/ralph/build` is a setup entrypoint only. It must not invoke `/ralph/run`.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (optional when project already exists)
- `objective=<goal-statement>` (required when creating a new project)
- `team=<team-key-or-name>` (default: `Studio`)
- `project_name=<name>` (optional override for project creation)
- `target_date=<YYYY-MM-DD>` (optional)
- `state=<state-name-or-id>` (optional issue target state for populate phase)
- `issue_count=<number>` (optional soft target for populate phase)
- `output=<path>` (default: `.cursor/ralph/{project-slug}/prd.json`)
- `branch=<branch-name>` (default: `feature/{project-slug}`)
- `include_done=true|false` (default: `false`)
- `audit_mode=read-only|propose-fixes` (default: `read-only`)
- `preflight_question_scan=true|false` (default: `true`)
- `dry_run=true|false` (default: `false`) — show phase plan without executing
- `stop_at=<phase>` (optional) — stop after the named phase: `create`, `populate`, `generate-prd`, or `audit`

## Required Gate

If neither `project` nor `objective` is supplied, stop and ask for one of:

- `project=<project-id-or-name>` for existing project setup
- `objective=<goal-statement>` to create a new project before setup

## Dry Run Mode

When `dry_run=true`, emit the phase plan (phase names, resolved inputs, and expected artifact paths) without executing any phases. Output format matches the normal completion response structure with `status=dry_run` for every phase.

## Stop-At Semantics

When `stop_at` is set, execute phases up to and including the named phase, then stop. Valid values:

| `stop_at` value | Last executed phase |
|---|---|
| `create` | Phase 1 only |
| `populate` | Phase 1 + Phase 2 |
| `generate-prd` | Phase 1 + Phase 2 + Phase 3 |
| `audit` | All phases (default full pipeline) |

Phases after `stop_at` report `status=skipped` in the completion response.

## Deterministic Build Phases

For each phase, emit:

- `BUILD_PHASE phase=<phase-name> status=start`
- `BUILD_PHASE phase=<phase-name> status=pass`
- `BUILD_PHASE phase=<phase-name> status=fail reason="<actionable-summary>"`

Stop immediately on first failed phase.

### Phase 1: `create-project` (when `project` is not provided)

Run `/linear/create-project` using:

- objective from `objective`
- optional `team`, `project_name`, `target_date`

Capture resolved `project.id`, `project.name`, and `project.url`.

If `project` was supplied, resolve it first and treat this phase as `pass (existing project)`.

### Phase 2: `populate-project`

Run `/linear/populate-project` for the resolved project with optional:

- `team`
- `state`
- `issue_count`

### Phase 3: `generate-prd-from-project`

Run `/linear/generate-prd-from-project` for the resolved project with:

- `team`
- `output` (default preserved)
- `branch` (default preserved)
- `include_done`

Preserve normal artifacts from manual flow:

- `prd.json` at configured output path
- `.cursor/ralph/{project-slug}/linear-snapshot.json`
- `run-log.jsonl` creation behavior from the underlying command

### Phase 4: `audit-project`

Run `/linear/audit-project` for the resolved project with:

- `team`
- `mode=<audit_mode>`
- `preflight_question_scan`

Audit output is terminal for this wrapper. Do not launch `/ralph/run`.

## Build State

Build progress is recorded to `.cursor/ralph/{project-slug}/build-state.json` after each phase:

```json
{
  "goal": "...",
  "project_id": "...",
  "project_name": "...",
  "project_url": "...",
  "team": "...",
  "prd_path": null,
  "phases": {
    "create": { "status": "complete", "completed_at": "2026-03-18T12:00:00Z" },
    "populate": { "status": "complete", "completed_at": "2026-03-18T12:01:00Z" },
    "generate_prd": { "status": "pending" },
    "audit": { "status": "pending" }
  }
}
```

Phase status values: `pending`, `running`, `complete`, `failed`, `skipped`.

When `project` is provided (resuming from an existing project), build state is loaded from the existing file if present. Completed phases are preserved and not re-executed.

## Script Runtime

`scripts/ralph-build.sh` provides a non-interactive entry point for environments where Linear MCP is not available. Since phases 1-2 require MCP interaction, the script:

- Emits phase-start/phase-end markers to stdout
- Writes build state to `.cursor/ralph/{project-slug}/build-state.json`
- Requires `--project-id <id>` when MCP is unavailable (skips create)
- Invokes `scripts/ralph-run.sh`-style prerequisite checks for generate-prd and audit phases

Usage:

```bash
scripts/ralph-build.sh \
  --goal "Add authentication to the API" \
  --team Studio \
  --project-id N43-500 \
  --stop-at generate-prd
```

## Failure Handling

If a phase fails, return:

1. Failed phase name + concise reason
2. Exact rerun command for that phase
3. Next unexecuted phase (if any)
4. Whether existing artifacts are still valid or should be regenerated
5. Build state path for resumption

## Completion Response

On success, return:

1. Resolved project identity (`id`, `name`, `url`)
2. Phase status table for all four phases
3. PRD artifact path + snapshot hash (if generated)
4. Audit readiness summary (ready/not-ready + critical findings)
5. Explicit next-step prompt:

`Build complete through audit. Do you want to continue to /ralph/run now?`

## Contract References

- Composite setup contract: `contracts/ralph/core/commands/build.md`
- Create project: `contracts/ralph/core/commands/create-project.md`
- Populate project: `contracts/ralph/core/commands/populate-project.md`
- Generate PRD: `contracts/ralph/core/commands/generate-prd-from-project.md`
- Audit project: `contracts/ralph/core/commands/audit-project.md`
- Workflow invariants: `contracts/ralph/core/linear-workflow.md`

## Safety

1. Do not skip or reorder setup phases.
2. Do not invoke `/ralph/run` from this wrapper.
3. Do not mutate unrelated projects/issues.
