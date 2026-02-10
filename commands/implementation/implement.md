> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Orchestration requires reasoning about state, delegation, and user intent -->

# Implement Feature

Orchestrate a complete feature implementation using the plan→execute→iterate workflow.

## Feature: $ARGUMENTS

## Workflow Overview

This command triggers the orchestrator pattern:

1. **Plan** - Create an implementation plan (via subagents/plan-feature.md)
2. **Review** - Present plan for user approval
3. **Execute** - Implement the plan (via subagents/execute.md)
4. **Iterate** - Gather feedback and refine as needed
5. **Complete** - Mark feature done when user confirms

## Process

### 1. Scan for Existing Session

Check if a feature session already exists:

```bash
# List active feature directories
ls -d .cursor/plans/*/ 2>/dev/null | grep -v DONE- | grep -v pr-reviews
```

If a matching feature directory exists:

- Read `agent-session.json` to understand current state
- Offer to resume from that state
- Show existing plan versions

### 2. Initialize New Feature Session

If starting fresh:

1. **Generate feature name** (kebab-case from description)
2. **Check for collisions** - append timestamp if directory exists
3. **Create directory**: `.cursor/plans/{feature-name}/`
4. **Create `agent-session.json`** with initial state (orchestrator does this BEFORE spawning subagent):
   ```json
   {
     "feature": "{feature-name}",
     "description": "{user's feature description}",
     "currentVersion": 1,
     "status": "planning",
     "created": "{ISO timestamp}",
     "lastUpdated": "{ISO timestamp}",
     "iterations": [{ "version": 1, "feedback": null }]
   }
   ```
5. **Spawn planning subagent**

### 3. Spawn Planning Subagent

Use the Task tool to spawn a planning subagent:

```
Task({
  subagent_type: "planner",
  description: "Create implementation plan v1",
  prompt: `## Parameters
  - Feature: {user's feature description}
  - Directory: .cursor/plans/{feature_name}/
  - Version: 1
  - Context: {any clarifications gathered}

  Create the plan and return a summary.`
})
```

### 4. Review Planning Results

When planning subagent returns:

1. **Update `agent-session.json`** (orchestrator does this after subagent returns):
   - Set status to `"awaiting-feedback"`
   - Update `lastUpdated` timestamp
2. Present plan summary to user
3. Show: task count, complexity, key risks
4. **Ask**: "Ready to execute, or do you have changes?"

**If user has changes:**

1. **Update `agent-session.json`** BEFORE spawning new planning subagent:
   - Record feedback in current iteration
   - Increment `currentVersion`
   - Add new iteration entry: `{ "version": N, "feedback": null }`
   - Set status to `"planning"`
   - Update `lastUpdated` timestamp
2. Spawn new planning subagent with version N

**If user approves:**

1. **Update `agent-session.json`**:
   - Set status to `"executing"`
   - Update `lastUpdated` timestamp
2. Proceed to execution

### 5. Spawn Execution Subagent

```
Task({
  subagent_type: "executor",
  description: "Execute implementation plan",
  prompt: `## Parameters
  - Plan: .cursor/plans/{feature_name}/plan-v{N}.md

  Execute all tasks, run validations, and return a report.
  Do NOT rename the directory to DONE-.`
})
```

### 6. Review Execution Results

When execution subagent returns:

1. **Update `agent-session.json`** (orchestrator does this after subagent returns):
   - Set status to `"awaiting-feedback"`
   - Update `lastUpdated` timestamp
2. Present execution report to user
3. Show: tasks completed, files changed, validation results
4. **Ask**: "Is this feature complete, or do you need another iteration?"

**If user needs iteration:**

1. Gather feedback on what to change
2. **Update `agent-session.json`** BEFORE spawning new planning subagent:
   - Record feedback in current iteration
   - Increment `currentVersion`
   - Add new iteration entry: `{ "version": N, "feedback": null }`
   - Set status to `"planning"`
   - Update `lastUpdated` timestamp
3. Return to step 3 (planning subagent with version N)

**If user confirms complete:**

- Proceed to completion

### 7. Mark Feature Complete

1. Update `agent-session.json` status to `"complete"`
2. Rename directory: `.cursor/plans/{feature-name}/` → `.cursor/plans/DONE-{feature-name}/`
3. Report final summary
4. Suggest commit message

## Session State

The `agent-session.json` file tracks:

```json
{
  "feature": "feature-name",
  "description": "Full feature description",
  "currentVersion": 2,
  "status": "awaiting-feedback",
  "created": "2026-02-03T10:30:00Z",
  "lastUpdated": "2026-02-03T14:45:00Z",
  "iterations": [
    { "version": 1, "feedback": null },
    { "version": 2, "feedback": "Add error handling for edge cases" }
  ]
}
```

## Iteration Flow

```
User describes feature
        ↓
[Plan v1] ← Subagent
        ↓
Review with user
        ↓
    ┌───┴───┐
    │ Changes? │
    └───┬───┘
    Yes ↓       No
        ↓       ↓
[Plan v2]   [Execute] ← Subagent
        ↓       ↓
        ↓   Review results
        ↓       ↓
        └───┬───┘
            │ Complete?
            ↓
        Yes ↓       No (iterate)
            ↓       ↓
      [DONE-]   [Plan vN+1]
```

## Recovery

### Lost Context

If chat context is lost, recover from filesystem:

1. List `.cursor/plans/` directories
2. Read `agent-session.json` from active directories
3. Offer to resume or start fresh

### Subagent Failure

If subagent fails:

1. Report error to user
2. Offer to retry
3. Offer manual fallback:
   - `/implementation/plan-feature` for manual planning
   - `/implementation/execute` for manual execution

## Example Usage

**User**: `/implement Add user authentication with OAuth`

**Agent**:

1. Creates `.cursor/plans/add-user-authentication-oauth/`
2. Spawns planning subagent
3. Presents plan: "Created 12-task plan (Medium complexity)..."
4. User: "Looks good, execute it"
5. Spawns execution subagent
6. Presents report: "Completed 12 tasks, all validations pass..."
7. User: "Complete!"
8. Renames to `DONE-add-user-authentication-oauth/`

## Notes

- Each planning/execution happens in isolated subagent context
- State persists in filesystem, not conversation memory
- User has approval checkpoint before each execution
- Iterations create versioned plans (plan-v1.md, plan-v2.md)
- Only user confirmation marks feature as DONE
