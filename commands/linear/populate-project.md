> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Requires converting project/milestone intent into a dependency-aware issue graph -->

# Populate Linear Project

Populate an existing Linear project with issues derived from its description and milestones.

This command expects the project to already exist and be well-defined.

Stage strategy default: this planning/decomposition step uses high-reasoning model behavior (see `contracts/ralph/core/stage-model-strategy.md`).

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `state=<state-name-or-id>` (optional; default resolves to backlog/todo state)
- `issue_count=<number>` (optional soft target)

Example:

```text
/linear/populate-project project="Ralph Wiggum Flow"
```

## Audit Gate (Required Prompt)

Before proceeding, if `/linear/audit-project` has **not** been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before we populate issues?`

If user declines, continue.

## Preconditions

Project must have:

1. Non-empty description
2. At least one milestone

If either is missing, stop and ask the user to update project definition first.

## Process

### 1. Load Project Context

Fetch project with milestones/resources:

```text
CallMcpTool: project-0-workspace-Linear / get_project
Arguments: { "query": "<project>", "includeMilestones": true, "includeResources": true }
```

### 2. Build Issue Plan

Generate issues from project + milestone outcomes.

Per issue, include:

1. Concise title
2. Goal-oriented description
3. Implementation notes for limited-context subagents
4. Acceptance criteria
5. Dependencies (`dependsOn`/blocking references)
6. Priority + point estimate derived from deterministic rubric
7. Metadata rationale section (estimated tokens, confidence, rubric factors)

For each draft issue, compute metadata with:

```bash
scripts/score-issue-metadata.sh \
  --calibration ".cursor/ralph/calibration.json" \
  --input "<draft-issue-json>"
```

Use scorer output fields directly:

- `priority` -> Linear priority
- `estimate` -> Linear estimate
- `estimatedTokens`, `confidence`, `lowConfidence`, `rationale` -> add to issue description under a `## Metadata Rationale` section

If `lowConfidence=true`, keep the issue in backlog but annotate metadata rationale clearly so `/linear/audit-project` can flag it.

The calibration snapshot at `.cursor/ralph/calibration.json` is maintained by Ralph's post-run retrospective flow when available. Missing calibration data must remain a safe fallback path.

Present planned issue list and ask user to approve before creating.

### 3. Resolve Status + Labels

Resolve target state:

- user-provided `state`, or
- backlog/todo-equivalent status

Ensure required labels exist:

- `Ralph`
- `PRD Ready`
- `Agent Generated`
- `Human Required`

Deprecated claim labels (`Ralph Queue`, `Ralph Claimed`, `Ralph Completed`) must **not** be added to new issues. These labels are deprecated per `contracts/ralph/core/claim-label-deprecation.md` and exist only as compatibility aliases for legacy integrations. If a project still has legacy consumers that require them, ensure the labels exist at the team level but do not apply them during issue creation.

### 4. Create Issues

Create approved issues under the project:

```text
CallMcpTool: project-0-workspace-Linear / create_issue
Arguments: {
  "title": "<issue_title>",
  "description": "<issue_description>",
  "team": "<team>",
  "project": "<project.id>",
  "state": "<resolved_state>",
  "priority": <priority_number>,
  "estimate": <issue_point_estimate>,
  "labels": ["Ralph", "PRD Ready", "Agent Generated", ...optional_domain_labels]
}
```

Do **not** add `Ralph Queue`, `Ralph Claimed`, or `Ralph Completed` to new issues. These deprecated claim labels are compatibility-only and not required for readiness, scheduling, or claim-state tracking. See `contracts/ralph/core/claim-label-deprecation.md`.

Then apply dependencies/relationships where supported.

### 5. Seed Dormant Closeout Issue

After all milestone-derived issues are created, seed exactly one **Project Closeout** issue using the template at `templates/project-closeout/closeout-issue-template.md`.

Properties:

| Field       | Value |
|-------------|-------|
| Title       | `<Project Name> - Project Closeout` |
| Priority    | 4 (Low) |
| Estimate    | 1 |
| Labels      | `Ralph`, `Agent Generated` |
| Status      | Backlog (dormant) |

Do **not** label the closeout issue with `PRD Ready` — it is not eligible for automation until promoted.

```text
CallMcpTool: project-0-workspace-Linear / create_issue
Arguments: {
  "title": "<Project Name> - Project Closeout",
  "description": "<rendered closeout template>",
  "team": "<team>",
  "project": "<project.id>",
  "state": "<backlog_state>",
  "priority": 4,
  "estimate": 1,
  "labels": ["Ralph", "Agent Generated"]
}
```

The closeout issue is **not** included in the user approval checkpoint at step 2 — it is created unconditionally as project infrastructure.

#### Auto-Promotion Lifecycle

The closeout issue follows a dormant-to-active lifecycle:

1. **Dormant (Backlog)** — Created during population. No action required.
2. **Promotion trigger** — When every other issue in the project reaches a terminal state (`Done` or `Canceled`), the closeout issue is promoted from Backlog to `Todo` and labeled `PRD Ready`.
3. **Active (Todo)** — Now eligible for Ralph automation or manual execution.
4. **Complete (Done)** — After the closeout checklist passes, the project itself can be marked Completed.

The promotion check runs at two points:

- **Ralph post-run**: after each issue completion in a `/ralph/run` loop, check whether the closeout issue should be promoted.
- **Manual audit**: `/linear/audit-project` reports closeout promotion readiness when applicable.

If the project already has a closeout issue (detected by title suffix `- Project Closeout`), skip seeding to prevent duplicates.

### 5A. Umbrella Decomposition Safety (Required When Replacing Broad Parent Issues)

> **Warning**: Canceling a parent issue in Linear auto-cascades to all children. Always unparent children or use the Done strategy before canceling a superseded umbrella. See `contracts/ralph/core/issue-decomposition-safety.md` for the full safety contract.

If existing umbrella issues are being split into narrower replacement slices, use this exact order:

1. Create all replacement child issues first as runnable backlog items.
2. Keep replacements out of parent/sub-issue hierarchy with the superseded umbrella issue.
3. Link replacements with `relatedTo`, `blockedBy`, or `blocks` only.
4. Verify replacement children remain runnable (not `Done`, not `Canceled`, no `Human Required`).
5. Terminalize the superseded umbrella issue only after step 4 passes.

**Terminalization decision matrix** (from the safety contract):

| Scenario | Strategy | Key Step |
|---|---|---|
| Umbrella partially implemented | **Done** + comment | No unparenting needed (Done doesn't cascade) |
| Umbrella never started | **Unparent** children → **Cancel** | Must unparent first (`parentId → null`) |
| Umbrella replaced entirely | **Unparent** children → **Cancel** | Must unparent first |
| External integrations depend on state | **Done** + comment | Safest — no cascade, no broken integrations |

For automated decomposition, use the helper script:

```bash
scripts/safe-decompose-issue.sh --parent <issue-id> --strategy <done|cancel> --dry-run
```

#### Cascade Prevention Checklist

Before terminalizing any superseded umbrella:

- [ ] All replacement issues exist and are in a runnable state (`Todo` or `Backlog`)
- [ ] Replacement issues are NOT in parent/sub-issue hierarchy with the umbrella
- [ ] If using `cancel` strategy: all existing children have been unparented (`parentId → null`)
- [ ] Superseded umbrella has a comment documenting the decomposition and replacement issue IDs

## Return Checkpoint

Return:

1. Created issue count (including the closeout issue)
2. Ordered issue table (priority + dependencies)
3. Closeout issue status (seeded / skipped-duplicate)
4. Confirmation prompt:

`Issues populated. Do you want to continue to /linear/generate-prd-from-project now?`

## PRD-Ready Template For Manual Issues

For human-authored issues that should still be automation-ready, use `templates/linear/prd-ready-issue.md` as the default structure.

## Agent-Created Issue Defaults

All agent-created issues (from this command, `/linear/create-issue`, retrospective follow-ups, or decomposition flows) must include:

1. **`## Metadata Rationale` section** with `priority`, `estimate`, `estimatedTokens`, `confidence`, `lowConfidence`, and `rubricFactors` fields.
2. **Labels**: `Ralph`, `PRD Ready`, `Agent Generated` at minimum. Domain labels as appropriate.
3. **Structural readiness sections**: `## Goal`, `## Acceptance Criteria`, `## Validation` at minimum.

Default values and heuristics are documented in `contracts/ralph/core/issue-creation-defaults.md`.

## Safety

1. Do not modify unrelated issues outside the target project.
2. Do not mark any generated issue as done.
3. Stop on ambiguous project resolution and ask user to choose.
