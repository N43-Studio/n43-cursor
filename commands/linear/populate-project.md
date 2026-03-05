> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Requires converting project/milestone intent into a dependency-aware issue graph -->

# Populate Linear Project

Populate an existing Linear project with issues derived from its description and milestones.

This command expects the project to already exist and be well-defined.

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
6. Point estimate based on predicted token consumption

Present planned issue list and ask user to approve before creating.

### 3. Resolve Status + Labels

Resolve target state:

- user-provided `state`, or
- backlog/todo-equivalent status

Ensure required labels exist:

- `Agent Generated`
- `Ralph`
- `Human Required`

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
  "labels": ["Agent Generated", "Ralph", ...optional_domain_labels]
}
```

Then apply dependencies/relationships where supported.

## Return Checkpoint

Return:

1. Created issue count
2. Ordered issue table (priority + dependencies)
3. Confirmation prompt:

`Issues populated. Do you want to continue to /linear/generate-prd-from-project now?`

## Safety

1. Do not modify unrelated issues outside the target project.
2. Do not mark any generated issue as done.
3. Stop on ambiguous project resolution and ask user to choose.
