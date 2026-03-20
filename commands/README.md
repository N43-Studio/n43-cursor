# Commands Directory

This directory contains Cursor commands organized by domain. Commands are markdown files that define agent behaviors and workflows.

## Directory Structure

```
.cursor/commands/
  ├── git/                        # Version control operations
  │   ├── commit.md               # Create conventional commits
  │   ├── push.md                 # Push + batch Linear sync
  │   ├── release-notes.md        # Generate human-readable release notes
  │   └── squash.md               # Squash branches for PR
  ├── linear/                     # Linear source-of-truth workflows
  │   ├── audit-project.md        # Audit project readiness for Ralph
  │   ├── review-queue.md         # Review/triage Needs Review + Needs Human issues
  │   ├── create-project.md       # Create a new project with description/milestones
  │   ├── populate-project.md     # Populate existing project with issues
  │   ├── generate-prd-from-project.md # Convert project issues to prd.json
  │   └── update-projects.md      # Project status updates from git activity
  ├── ralph/                      # Ralph setup/runtime entrypoints (Cursor/Codex/script parity)
  │   ├── build.md                # Single-entry setup wrapper through audit
  │   ├── morning-briefing.md     # Generate morning briefing from overnight artifacts
  │   └── run.md                  # Invoke canonical scripts/ralph-run.sh
  ├── code-review/                # PR review workflows
  │   ├── review-pr.md            # Generate PR review document
  │   ├── interactive-review.md   # Refine review interactively
  │   ├── organize-pr-for-github.md # Reformat review for GitHub UI
  │   ├── generate-morning-briefing.md # Build deterministic morning briefing artifacts
  │   └── prepare-overnight-ralph-review.md # Build overnight Ralph review context
  ├── project-closeout/           # Branch closeout & merge preparation
  │   ├── closeout-workflow.md    # Canonical 6-stage closeout workflow
  │   └── run-closeout.md        # Orchestrated closeout command
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
| `push.md`   | Push to origin + batch Linear issue sync           |
| `release-notes.md` | Generate release notes from a git range     |
| `squash.md` | Squash branch commits with plan/mapping/verification artifacts |

### Ralph (`/ralph/`)

Commands for Ralph setup and runtime entrypoints across Cursor and Codex surfaces.
Iterative execution is supported via all three equivalent entrypoints:
- `scripts/ralph-run.sh`
- Cursor `/ralph/run`
- Codex `ralph-run` skill

| Command  | Description                                  |
| -------- | -------------------------------------------- |
| `build.md` | Orchestrate setup phases (`create -> populate -> prd -> audit`) |
| `run.md` | Invoke `scripts/ralph-run.sh` with arguments |
| `morning-briefing.md` | Generate morning briefing from overnight run artifacts |

### Linear (`/linear/`)

Commands for Linear-first planning, issue generation, and PRD generation.

| Command                        | Description                                                    |
| ------------------------------ | -------------------------------------------------------------- |
| `audit-project.md`             | Audit project consistency/readiness for Ralph automation       |
| `create-project.md`            | Create net-new Linear project with description + milestones    |
| `create-issue.md`              | Create one implementation-ready issue with approval checkpoint |
| `review-queue.md`              | Deterministically review/transition `Needs Review` + `Needs Human` queue |
| `populate-project.md`          | Populate existing project with dependency-aware issues         |
| `generate-prd-from-project.md` | Generate Ralph-compatible `prd.json` from project issue state |
| `update-projects.md`           | Scan git activity; project status updates + issue checks        |

### Code Review (`/code-review/`)

Commands for PR review workflows.

| Command                            | Description                                           |
| ---------------------------------- | ----------------------------------------------------- |
| `review-pr.md`                     | Generate comprehensive PR review document             |
| `interactive-review.md`            | Refine review through conversation                    |
| `organize-pr-for-github.md`        | Reformat review for GitHub PR UI copy-paste          |
| `generate-morning-briefing.md`     | Generate deterministic morning briefing markdown + JSON |
| `prepare-overnight-ralph-review.md` | Generate overnight Ralph review context + checklist |

### Project Closeout (`/project-closeout/`)

Commands for transitioning a long-lived branch to a merge-ready end state.

| Command                | Description                                                      |
| ---------------------- | ---------------------------------------------------------------- |
| `closeout-workflow.md` | 6-stage closeout: inventory → triage → coherence → release → squash → Linear |
| `run-closeout.md`      | Orchestrate all 6 stages into a single closeout packet           |

Related template: `templates/project-closeout/closeout-checklist.md`

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
/git/push
/linear/update-projects
/linear/audit-project project="Ralph Wiggum Flow"
/linear/create-project Add tests to the repo
/linear/create-issue project="Ralph Wiggum Flow" objective="Add smoke test command"
/linear/populate-project project="Ralph Wiggum Flow"
/linear/generate-prd-from-project project="Ralph Wiggum Flow"
/ralph/build project="Ralph Wiggum Flow"
/ralph/run prd=".cursor/ralph/ralph-wiggum-flow/prd.json"
/ralph/morning-briefing run_log="run-log.jsonl" project_slug="ralph-wiggum-flow"
/code-review/generate-morning-briefing run_log="run-log.jsonl" retrospective=".cursor/ralph/ralph-wiggum-flow/retrospective.json" review_queue=".cursor/ralph/ralph-wiggum-flow/review-queue.json"
/code-review/prepare-overnight-ralph-review run_log="run-log.jsonl" results_dir=".ralph/results"
/project-closeout/run-closeout project="Ralph Wiggum Flow"
/project-closeout/run-closeout project="Ralph Wiggum Flow" --dry-run
/implementation/plan-feature Add user authentication
/implementation/execute .cursor/plans/feature-name/plan-v1.md
```

### Linear Workflow Order

Expected sequence (manual phases):

1. Optional: `/linear/audit-project`
2. `/linear/create-project`
3. `/linear/populate-project`
4. `/linear/generate-prd-from-project`
5. `/ralph/run`

Single-entry setup alternative:

1. `/ralph/build` (runs `create-project -> populate-project -> generate-prd-from-project -> audit-project`)
2. `/ralph/run`

After `prd.json` is generated and audited, iterations should run continuously via any supported runtime entrypoint (`scripts/ralph-run.sh`, Cursor `/ralph/run`, Codex `ralph-run`) until a deterministic stop condition.

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
