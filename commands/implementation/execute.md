> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Code implementation following detailed plan specifications -->

# Execute Plan

Execute an implementation plan step-by-step.

## Plan to Execute

Read plan file: `$ARGUMENTS`

If no argument provided, list available plans in `.cursor/plans/` and ask which to execute.

## Usage Modes

This command can be run in two ways:

| Mode                 | How                                    | When                                      |
| -------------------- | -------------------------------------- | ----------------------------------------- |
| **Standalone**       | Run `/implementation/execute` directly | Manual workflow, full control             |
| **Via Orchestrator** | Subagent reads this methodology        | Automated via `/implementation/implement` |

Both modes use the same execution methodology. The key difference is **who marks completion**:

- **Standalone**: This command renames the directory to `DONE-` after execution
- **Orchestrator**: The orchestrator handles completion marking after user confirmation

---

## Execution Instructions

### 0. Check Session Context

If executing a plan from a feature directory (e.g., `.cursor/plans/{feature}/plan-v{N}.md`):

1. Read `agent-session.json` from the feature directory
2. Note the current version and any previous iteration feedback
3. Update status to `"executing"` at start of execution

```json
{
  "status": "executing",
  "lastUpdated": "{current ISO timestamp}"
}
```

### 1. Read and Understand

- Read the ENTIRE plan carefully
- Understand all tasks and their dependencies
- Note the validation commands to run
- Review the testing strategy
- Read all files listed in "Relevant Codebase Files" section

### 2. Execute Tasks in Order

For EACH task in "Step by Step Tasks":

#### a. Navigate to the task

- Identify the file and action required
- Read existing related files if modifying

#### b. Implement the task

- Follow the detailed specifications exactly
- Maintain consistency with existing code patterns
- Include proper type hints and documentation
- Add structured logging where appropriate

#### c. Verify as you go

- After each file change, check syntax
- Ensure imports are correct
- Verify types are properly defined
- Run the task's validation command if specified

### 3. Implement Testing Strategy

After completing implementation tasks:

- Create all test files specified in the plan
- Implement all test cases mentioned
- Follow the testing approach outlined
- Ensure tests cover edge cases

### 4. Run Validation Commands

Execute ALL validation commands from the plan in order:

```bash
# Run each command exactly as specified in plan
```

If any command fails:

- Fix the issue
- Re-run the command
- Continue only when it passes

### 5. Final Verification

Before completing:

- ✅ All tasks from plan completed
- ✅ All tests created and passing
- ✅ All validation commands pass
- ✅ Code follows project conventions
- ✅ Documentation added/updated as needed

### 6. Mark Plan as Executed

**Important**: Only mark as DONE when the user confirms the feature is complete. If iterating, do NOT mark as DONE.

#### For Directory-Based Plans (Preferred)

After user confirms completion, rename the **directory** with the `DONE-` prefix:

```bash
# Rename the feature directory
mv .cursor/plans/{feature-name}/ .cursor/plans/DONE-{feature-name}/
```

Also update `agent-session.json` status to `"complete"` before renaming.

**Example:**

- Before: `.cursor/plans/add-user-authentication/` (tracked)
- After: `.cursor/plans/DONE-add-user-authentication/` (ignored)

#### For Legacy Flat Files

For backwards compatibility with flat file plans:

```bash
# Rename the executed plan
mv .cursor/plans/{plan-name}.md .cursor/plans/DONE-{plan-name}.md
```

#### When NOT to Mark as DONE

Do NOT mark as DONE if:

- User wants another iteration (feedback → new plan → execute again)
- Running as a subagent (orchestrator handles completion)
- User hasn't explicitly confirmed the feature is complete

**Ask**: "Is this feature complete, or do you need another iteration?"

**Example:**

- Before: `.cursor/plans/add-user-authentication.md` (tracked)
- After: `.cursor/plans/DONE-add-user-authentication.md` (ignored)

## Output Report

Provide summary:

### Completed Tasks

- List of all tasks completed
- Files created (with paths)
- Files modified (with paths)

### Tests Added

- Test files created
- Test cases implemented
- Test results

### Validation Results

```bash
# Output from each validation command
```

### Issues Encountered

- Any deviations from the plan
- Problems solved during implementation
- Remaining concerns (if any)

### Ready for Commit

- Confirm all changes are complete
- Confirm all validations pass
- Suggest commit message

## Notes

- If you encounter issues not addressed in the plan, document them
- If you need to deviate from the plan, explain why
- If tests fail, fix implementation until they pass
- Don't skip validation steps
- Ask for clarification if a task is ambiguous
