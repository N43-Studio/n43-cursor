> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Long-running orchestration with state sync and freshness checks requires strict control flow -->

> **Agent**: `.cursor/agents/ralph-runner.md` - Use for delegated per-issue execution via the orchestrator

# Run Ralph (Agent-Orchestrated)

Run Ralph using subagents instead of `ralph.sh`.

`/ralph/run` can be invoked at any point. If prerequisites are missing, route the user into the Linear workflow:

`/linear/create-project` -> `/linear/populate-project` -> `/linear/generate-prd-from-project`

Optional audit before any step:

`/linear/audit-project`

## Input

`$ARGUMENTS` supports:

- `prd=<path>` (optional)
- `linear_project=<project-id-or-name>` (optional)
- `linear_team=<team-key-or-name>` (default: `Studio`)
- `progress=<path>` (default: `progress.txt`)
- `max=<number>` (default: `5`)
- `autocommit=true|false` (default: `true`)
- `sync_linear=true|false` (default: `true` when `linear_project` provided)
- `refresh_linear_each_iteration=true|false` (default: `true` when `linear_project` provided)
- `usage_limit=<token-or-cost-budget>` (optional)

## Audit Gate (Required Prompt)

Before proceeding, if `/linear/audit-project` has **not** been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before starting Ralph?`

If user declines, continue.

## Prerequisite Routing

If prerequisites are missing, ask:

`Prerequisites are missing. Do you want to go through /linear/create-project -> /linear/populate-project -> /linear/generate-prd-from-project now?`

Missing prerequisites include:

1. No `prd` and no `linear_project`
2. `linear_project` resolves but has zero issues
3. `prd` missing required `issues` schema
4. `prd` references Linear source but is stale against current Linear snapshot hash

## Freshness Check (Cheap + Reliable)

If PRD contains `sourceLinearSnapshot.hash`:

1. Recompute current Linear snapshot hash from minimal stable fields:
   - project: `id`, `updatedAt`
   - issues (sorted): `id`, `identifier`, `updatedAt`, `state`, `priority`, `estimate`, `labels`
2. Compare with PRD hash.
3. If mismatch:
   - interrupt run
   - ask user to regenerate:
     - `/linear/generate-prd-from-project project=<project>`

When `refresh_linear_each_iteration=true`, run this check before each next-issue selection.

## Process

### 1. Resolve Source

1. If `prd` provided, load it.
2. Else if `linear_project` provided:
   - generate PRD via `/linear/generate-prd-from-project`
3. Else route user through prerequisite workflow.

### 2. Validate PRD

Required structure:

```json
{
  "branchName": "feature/my-branch",
  "issues": [
    {
      "issueId": "N43-123",
      "title": "Issue title",
      "description": "What to build",
      "priority": 1,
      "passes": false
    }
  ]
}
```

### 3. Preflight Linear Sync (if enabled)

Resolve:

1. Project exists
2. Team statuses include:
   - `In Progress`
   - `Needs Review`
3. Required labels exist:
   - `Agent Generated`
   - `Ralph`
   - `Human Required`
4. Project lead exists for escalation assignment

### 4. Pre-Run Checkpoint

Show:

1. Pending issues
2. Max iterations
3. Usage limit (if set)

Ask:

`Ready to run Ralph now?`

### 5. Iteration Loop

For each iteration:

1. Re-check PRD freshness hash (if applicable).
2. Select next pending issue (`passes != true`) by priority/issueId.
3. If `sync_linear=true`, set issue to `In Progress`.
4. Spawn `ralph-runner` for exactly one issue.
5. On success:
   - update PRD issue pass state
   - if PR URL exists, set issue `Needs Review`
   - otherwise keep `In Progress` with follow-up comment
6. On failure:
   - keep `passes=false`
   - add summary comment
   - add `Human Required` label
   - assign issue to project lead
7. Stop on:
   - no pending issues
   - `max` reached
   - `usage_limit` reached
   - freshness hash mismatch

## Completion

Complete only when all pending issues pass.

Return:

1. Iteration count
2. Issue outcomes
3. Linear sync outcomes
4. Remaining issues (must be zero for complete)

## Notes

1. Do not use `ralph.sh` in this workflow.
2. Keep all issue ordering deterministic.
3. Never silently continue after a freshness mismatch.
