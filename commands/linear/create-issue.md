> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Requires translating partial requirements into one implementation-ready, dependency-safe issue -->

# Create Single Linear Issue

Interactively generate one implementation-ready Linear issue without running full project population.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `objective=<text>` (required intent)
- `scope=<text>` (optional)
- `constraints=<text>` (optional)
- `state=<state-name-or-id>` (optional; default resolves backlog/todo state)
- `blocked_by=<csv>` (optional issue identifiers)
- `blocks=<csv>` (optional issue identifiers)

## Audit Gate (Required Prompt)

Before proceeding, if `/linear/audit-project` has **not** been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before we create this issue?`

If user declines, continue.

## Process

### 1. Resolve Project Context

Fetch project details and confirm target project/team resolution.

### 2. Build One PRD-Ready Draft

Generate exactly one draft issue with sections aligned to `templates/linear/prd-ready-issue.md`:

1. Goal and context
2. Implementation notes (scope, expected files/components, non-goals, edge cases)
3. Explicit dependencies (`blockedBy` and `blocks`)
4. Acceptance criteria
5. Validation expectations
6. Point estimate + priority rationale

Run deterministic metadata scoring before approval:

```bash
scripts/score-issue-metadata.sh \
  --calibration ".cursor/ralph/calibration.json" \
  --input "<draft-issue-json>"
```

Use scorer output values as the authoritative metadata:

- `priority`
- `estimate`
- `estimatedTokens`
- `confidence`
- `lowConfidence`
- `rationale`

Include these in the draft issue body under `## Metadata Rationale`.

### 3. Resolve Labels And Status

Apply readiness taxonomy from `contracts/ralph/core/readiness-taxonomy.md`:

- `Ralph`
- `PRD Ready`
- `Agent Generated`
- Exclude `Human Required` unless user explicitly requests escalation state.

Resolve target state via explicit input or backlog/todo fallback.

### 4. User Approval Checkpoint (Required)

Present the final single-issue draft and ask:

`Ready to create this issue in Linear?`

If user does not approve, do not call `save_issue`.

### 5. Create Issue

On approval, call `save_issue` once with:

- title, description, team, project, state
- labels and rubric-derived estimate/priority
- optional `blockedBy` / `blocks`

## Return

Return:

1. Created issue identifier + URL
2. Applied labels/state/estimate
3. Dependency links set (if any)
4. Suggested next step:

`Do you want to continue to /linear/generate-prd-from-project now?`

## Safety

1. Never create more than one issue per invocation.
2. Never skip the approval checkpoint.
3. Never apply `Human Required` unless explicitly requested.
4. Stop and ask user when project resolution is ambiguous.
