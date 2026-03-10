> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Requires deterministic transformation + integrity metadata for safe long-running automation -->

# Generate PRD From Project

Generate a Ralph-compatible `prd.json` from an existing Linear project's issues.

Interpretation: `project-issues-to-prd-json`.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `output=<path>` (default: `.cursor/ralph/{project-slug}/prd.json`)
- `branch=<branch-name>` (optional override; default: `feature/{project-slug}`)
- `include_done=true|false` (default: `false`)

Example:

```text
/linear/generate-prd-from-project project="Ralph Wiggum Flow"
```

## Audit Gate (Required Prompt)

Before proceeding, if `/linear/audit-project` has **not** been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before generating prd.json?`

If user declines, continue.

## Preconditions

Project must have at least one issue.

If zero issues exist, stop with remediation:

`Run /linear/populate-project project=<project-id-or-name> first.`

## Process

### 1. Fetch Project + Issues

```text
CallMcpTool: project-0-workspace-Linear / get_project
Arguments: { "query": "<project>", "includeMilestones": true, "includeResources": true }
```

```text
CallMcpTool: project-0-workspace-Linear / list_issues
Arguments: { "project": "<resolved_project_id>", "team": "<team>", "limit": 250 }
```

Exclude done/canceled issues unless `include_done=true`.

### 2. Build Canonical Linear Snapshot (For Freshness Checks)

Create canonical snapshot payload using only stable fields, sorted by issue identifier:

- project: `id`, `updatedAt`
- each issue: `id`, `identifier`, `updatedAt`, `state`, `priority`, `estimate`, `labels`

Serialize as canonical JSON (stable key order) and compute:

- `linearSnapshotHash = sha256(canonical_json_v1)`

### 3. Normalize to PRD Schema

For each issue:

- `issueId` = issue identifier (e.g., `N43-123`)
- `linearIssueId` = issue UUID
- `title`
- `description`
- `priority`
- `status` (Linear state name)
- `labels` (array of label names)
- `dependsOn`
- `estimatedTokens` (optional; prefer rubric-derived value from issue metadata rationale)
- `passes = false`

Sort by:

1. `priority` ascending
2. `issueId` ascending

### 4. Write Artifacts

Write `prd.json`:

```json
{
  "featureName": "<project_name>",
  "branchName": "feature/<project-slug>",
  "sourceLinearProject": {
    "id": "<project_id>",
    "name": "<project_name>",
    "url": "<project_url>"
  },
  "sourceLinearSnapshot": {
    "algorithm": "sha256-canonical-json-v1",
    "hash": "<linearSnapshotHash>",
    "capturedAt": "<ISO timestamp>",
    "projectUpdatedAt": "<project_updated_at>",
    "issueCount": 12
  },
  "generatedAt": "<ISO timestamp>",
  "issues": []
}
```

Write sidecar snapshot:

- `.cursor/ralph/{project-slug}/linear-snapshot.json` (canonical payload used for hash)

Create `run-log.jsonl` if missing (append-only structured run log).
Optionally create `progress.txt` as a human-readable companion when requested.

## Return Checkpoint

Return:

1. `prd.json` path
2. `sourceLinearSnapshot.hash`
3. Issue count
4. Confirmation prompt:

`PRD generated. Do you want to continue to /ralph/run now?`

## Safety

1. Never delete existing PRD issues unless user explicitly asks to overwrite.
2. Fail on ambiguous project resolution.
3. Fail fast when issue count is zero.
