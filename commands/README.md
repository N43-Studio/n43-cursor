# Commands Directory

This directory contains Cursor commands organized by domain. Commands are markdown files that define agent behaviors and workflows.

## Directory Structure

```
.cursor/commands/
  ├── git/                        # Version control operations
  │   ├── commit.md               # Create conventional commits
  │   └── squash.md               # Squash branches for PR
  ├── linear/                     # Linear source-of-truth workflows
  │   ├── audit-project.md        # Audit project readiness for Ralph
  │   ├── create-project.md       # Create a new project with description/milestones
  │   ├── populate-project.md     # Populate existing project with issues
  │   └── generate-prd-from-project.md # Convert project issues to prd.json
  ├── ralph/                      # Ralph terminal-script wrappers
  │   └── run.md                  # Invoke canonical scripts/ralph-run.sh
  ├── code-review/                # PR review workflows
  │   ├── review-pr.md            # Generate PR review document
  │   ├── interactive-review.md   # Refine review interactively
  │   └── organize-pr-for-github.md # Reformat review for GitHub UI
  ├── implementation/             # Feature planning & execution
  │   ├── plan-feature.md         # Standalone planning
  │   ├── execute.md              # Standalone execution
  │   ├── implement.md            # Orchestrated workflow
  │   └── validate.md             # Validation checks
  └── README.md                   # This file
```

## Command Categories

### Git (`/git/`)

Commands for version control operations.

| Command     | Description                                        |
| ----------- | -------------------------------------------------- |
| `commit.md` | Create conventional commits with proper formatting |
| `squash.md` | Squash branch commits for clean PR history         |

### Ralph (`/ralph/`)

Commands for human-in-the-loop wrappers around canonical Ralph scripts.
Ralph iterations do not run via subagents; they run via `scripts/ralph-run.sh`.

| Command  | Description                                  |
| -------- | -------------------------------------------- |
| `run.md` | Invoke `scripts/ralph-run.sh` with arguments |

### Linear (`/linear/`)

Commands for Linear-first planning, issue generation, and PRD generation.

| Command                        | Description                                                    |
| ------------------------------ | -------------------------------------------------------------- |
| `audit-project.md`             | Audit project consistency/readiness for Ralph automation       |
| `create-project.md`            | Create net-new Linear project with description + milestones    |
| `populate-project.md`          | Populate existing project with dependency-aware issues         |
| `generate-prd-from-project.md` | Generate Ralph-compatible `prd.json` from project issue state |

### Code Review (`/code-review/`)

Commands for PR review workflows.

| Command                       | Description                                    |
| ----------------------------- | ---------------------------------------------- |
| `review-pr.md`                | Generate comprehensive PR review document      |
| `interactive-review.md`       | Refine review through conversation             |
| `organize-pr-for-github.md`  | Reformat review for GitHub PR UI copy-paste    |

### Implementation (`/implementation/`)

Commands for feature planning and execution.

| Command           | Description                                        |
| ----------------- | -------------------------------------------------- |
| `plan-feature.md` | Generate detailed implementation plan (standalone) |
| `execute.md`      | Execute an implementation plan (standalone)        |
| `implement.md`    | **Orchestrated** plan→execute→iterate workflow     |
| `validate.md`     | Run validation checks                              |

## Native Agents (`.cursor/agents/`)

Custom subagents auto-discovered by Cursor. These are the preferred way to define subagents.

| Agent          | Description                           | Model Tier      |
| -------------- | ------------------------------------- | --------------- |
| `planner.md`   | Creates detailed implementation plans | Tier 1 (Opus)   |
| `executor.md`  | Executes implementation plans         | Tier 2 (Sonnet) |
| `validator.md` | Runs validation checks                | Tier 3 (Fast)   |
| `reviewer.md`  | Conducts autonomous PR code reviews   | Tier 1 (Opus)   |
| `squasher.md`  | Squashes branches for PR readiness    | Tier 2 (Sonnet) |

## Model Selection

See `.cursor/rules/model-selection.mdc` for recommended models per command.
Each command file includes a `<!-- Recommended Model -->` comment header.

## Usage

### Direct Invocation

Run commands directly in the chat:

```
/git/commit
/linear/audit-project project="Ralph Wiggum Flow"
/linear/create-project Add tests to the repo
/linear/populate-project project="Ralph Wiggum Flow"
/linear/generate-prd-from-project project="Ralph Wiggum Flow"
/ralph/run prd=".cursor/ralph/ralph-wiggum-flow/prd.json"
/implementation/plan-feature Add user authentication
/implementation/execute .cursor/plans/feature-name/plan-v1.md
```

### Linear Workflow Order

Expected sequence:

1. Optional: `/linear/audit-project`
2. `/linear/create-project`
3. `/linear/populate-project`
4. `/linear/generate-prd-from-project`
5. `/ralph/run`

After `prd.json` is generated and audited, iterations should run continuously through `scripts/ralph-run.sh` until a deterministic stop condition.

### Orchestrated Workflow

For automated plan→execute→iterate cycles:

```
/implementation/implement Add user authentication with OAuth
```

This spawns isolated subagents for planning and execution, managing state automatically.

## Standalone vs Orchestrated

| Aspect         | Standalone                                                | Orchestrated                |
| -------------- | --------------------------------------------------------- | --------------------------- |
| **Commands**   | `/implementation/plan-feature`, `/implementation/execute` | `/implementation/implement` |
| **Context**    | Same chat, manual handoff                                 | Fresh context per subagent  |
| **State**      | Manual tracking                                           | `agent-session.json`        |
| **Iterations** | User manages versions                                     | Automatic versioning        |
| **Completion** | User marks DONE                                           | Orchestrator marks DONE     |

### When to Use Standalone

- Simple features
- You want full control over the process
- Debugging or learning the workflow

### When to Use Orchestrated

- Complex features with iterations
- You want automated state management
- Context isolation is important

## Subagent Pattern

The orchestrator uses the Task tool to spawn native subagents from `.cursor/agents/`:

1. **Planning Subagent** (`planner`): Follows methodology from `implementation/plan-feature.md`
2. **Execution Subagent** (`executor`): Follows methodology from `implementation/execute.md`
3. **Validation Subagent** (`validator`): Follows methodology from `implementation/validate.md`
4. **Review Subagent** (`reviewer`): Follows methodology from `code-review/review-pr.md`
5. **Squash Subagent** (`squasher`): Follows methodology from `git/squash.md`
Subagents return results to the orchestrator, which presents them to the user with approval checkpoints.

## Skills (`.cursor/skills/`)

Auto-discovered knowledge modules with progressive disclosure. Each skill has a concise `SKILL.md` entry point and supporting reference files.

| Skill             | Description                                              | Source                        |
| ----------------- | -------------------------------------------------------- | ----------------------------- |
| `git-workflow`    | Git conventions, commits, branches, Linear integration   | Migrated from `references/`   |
| `react-frontend`  | React + TypeScript + Tailwind best practices             | Migrated from `references/`   |
| `deployment`      | Docker, environment config, Cloud Run deployment         | Migrated from `references/`   |
| `testing-logging` | Testing strategies and structured logging patterns       | Migrated from `references/`   |
| `pr-review`       | Code review severity levels, feedback types, conventions | Extracted from `review-pr.md` |

## Related Documentation

- `.cursor/rules/orchestrator.mdc` - Orchestrator agent behavior
- `.cursor/plans/README.md` - Plan directory structure and lifecycle
- `.cursor/skills/` - Auto-discovered knowledge modules (git, React, deployment, testing, PR review)
- `.cursor/references/` - _Deprecated_ — migrated to `.cursor/skills/`
