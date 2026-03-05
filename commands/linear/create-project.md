> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Collaborative project shaping and milestone design require high-context reasoning -->

# Create Linear Project

Create a **net-new** Linear project through a collaborative design process, including:

1. Project description
2. Milestones
3. Core metadata required for downstream automation

This command does **not** populate issues. Use `/linear/populate-project` next.

## Input

`$ARGUMENTS` is a goal statement, for example:

```text
/linear/create-project Add tests to the repo
```

Optional key/value tokens:

- `team=<team-key-or-name>` (default: `Studio`)
- `project_name=<name>` (optional override)
- `target_date=<YYYY-MM-DD>` (optional)

## Audit Gate (Required Prompt)

Before proceeding, if `/linear/audit-project` has **not** been run in the current conversation, ask:

`Do you want to run /linear/audit-project first before we create this project?`

If user declines, continue.

## Collaborative Process

### 1. Clarify and Frame

Collaboratively confirm:

1. Project objective
2. Non-goals
3. Success criteria
4. Target timeline
5. Team scope

### 2. Draft Project Definition

Draft:

1. Project name
2. Description (problem, approach, done definition)
3. Milestone plan (ordered, outcome-based)

Present draft and ask for user approval before creation.

### 3. Create Project in Linear

Create the project:

```text
CallMcpTool: project-0-workspace-Linear / create_project
Arguments: {
  "name": "<project_name>",
  "description": "<approved_project_description>",
  "team": "<team>",
  "targetDate": "<optional_target_date>"
}
```

Capture:

- `project.id`
- `project.name`
- `project.url`
- `project.status`

### 4. Add Milestones

Add approved milestones to the project using Linear project update/milestone APIs available in MCP.

If milestone write is unavailable in MCP:

1. Stop and report limitation.
2. Provide milestone payload for manual apply.
3. Resume only after milestones exist on the project.

### 5. Return Checkpoint

Return:

1. Project summary
2. Milestone list
3. Confirmation prompt:

`Project created. Do you want to continue to /linear/populate-project now?`

## Safety

1. This command should always create a new project.
2. Do not repurpose existing projects here.
3. Do not create issues in this step.
