# n43-cursor

Centralized Cursor IDE agent workflow configuration. Provides a consistent set of agents, commands, skills, rules, and references for AI-assisted development across all your projects.

## Prerequisites

| Tool | Required For | Install |
| ---- | ------------ | ------- |
| [Node.js](https://nodejs.org/) 18+ | Script runtime | `brew install node` or [nvm](https://github.com/nvm-sh/nvm) |
| [jq](https://jqlang.github.io/jq/) | JSON processing in all scripts | `brew install jq` |
| [GitHub CLI](https://cli.github.com/) | Linear sync, PR workflows | `brew install gh` |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | MCP config generation | [Create token](https://github.com/settings/tokens) |

**Optional (for terminal-based Ralph execution):**

| Tool | Required For | Install |
| ---- | ------------ | ------- |
| [Codex CLI](https://github.com/openai/codex) | `scripts/ralph-run.sh` terminal backend | `npm install -g @openai/codex` |

> The Codex CLI is only required if you run Ralph from the terminal via `scripts/ralph-run.sh`. The Cursor `/ralph/run` command works entirely within Cursor's agent system and does not need it.

## Getting Started with Ralph

Ralph takes a Linear project and executes its issues one-by-one through AI agents, handling dependency ordering, status transitions, commits, and retrospectives.

### 1. Install n43-cursor into your project

```bash
git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor
bash .n43-cursor/scripts/setup.sh install
```

### 2. Choose your execution surface

| Surface | Command | Codex CLI Required? |
| ------- | ------- | ------------------- |
| **Cursor** (recommended) | `/ralph/run` slash command | No |
| **Terminal** | `scripts/ralph-run.sh --prd <path>` | Yes |
| **Terminal (dry run)** | `RALPH_ISSUE_EXECUTOR_CMD=scripts/mock-issue-agent.sh scripts/ralph-run.sh --prd <path>` | No |

### 3. Build a project (fast path)

In Cursor, run:

```
/ralph/build
```

This chains: create Linear project -> populate with issues -> generate PRD -> audit readiness. Then run:

```
/ralph/run
```

### 4. Build a project (manual path)

For more control over each step:

```
/linear/create-project       # define the project + milestones
/linear/populate-project     # generate issues from project scope
/linear/generate-prd-from-project   # export to prd.json
/linear/audit-project        # validate readiness (optional but recommended)
/ralph/run prd=.cursor/ralph/<project-slug>/prd.current.json
```

### Issue Authoring Requirements

Every issue Ralph executes must have four sections in its description:

| Section | Purpose |
| ------- | ------- |
| `## Goal` | What the issue achieves |
| `## Context` | Relevant background and constraints |
| `## Acceptance Criteria` | Checklist of done conditions |
| `## Validation` | How to verify the work (commands, checks) |

Issues missing these sections will fail structural readiness and be skipped. The `/linear/populate-project` command generates issues in this format automatically.

See `contracts/ralph/core/readiness-taxonomy.md` for full readiness criteria.

### Swapping the Execution Backend

The terminal-based flow uses `scripts/configured-issue-agent.sh`, which delegates to a configurable backend via the `RALPH_ISSUE_EXECUTOR_CMD` environment variable:

```bash
# Default: Codex CLI
scripts/ralph-run.sh --prd prd.json

# Custom backend
RALPH_ISSUE_EXECUTOR_CMD=my-custom-agent.sh scripts/ralph-run.sh --prd prd.json

# Smoke test (no-op agent, always succeeds)
RALPH_ISSUE_EXECUTOR_CMD=scripts/mock-issue-agent.sh scripts/ralph-run.sh --prd prd.json
```

Any backend must implement the CLI issue execution contract: read `--input-json`, write `--output-json` with the result schema defined in `contracts/ralph/core/cli-issue-execution-contract.md`.

## Suggested Developer Workflow

### Feature Development: Brainstorm → Plan → Build

The recommended workflow for implementing features and changes:

1. **Brainstorm** — For new features, the `superpowers/brainstorming` skill triggers automatically. It walks through clarifying requirements one question at a time, proposes 2–3 approaches with trade-offs, and gates on design approval before any code is written. This prevents wasted implementation cycles on under-specified ideas.

2. **Plan Mode** — Press `Shift+Tab` in the Cursor agent input to enter Plan Mode. The agent researches your codebase, generates a structured markdown plan with file paths and code references, and asks clarifying questions. Edit the plan directly before building.

3. **Build** — Click **Build** to execute the plan. Watch diffs in real-time. If the result drifts from intent, revert and refine the plan rather than patching with follow-up prompts — this almost always produces cleaner results.

4. **Iterate** — For complex multi-session features, save the plan to workspace (`.cursor/plans/`) for cross-session continuity and recovery. The orchestrator rule tracks iteration state in `agent-session.json` when using the full orchestrated flow.

**When to use which approach:**

| Situation | Recommended approach |
| --------- | -------------------- |
| Quick fix, routine change | Agent Mode directly |
| New feature or unclear scope | Brainstorm → Plan Mode → Build |
| Multi-system / architectural change | Brainstorm → Plan Mode → Build (save to workspace) |
| Well-scoped project with multiple issues | [Ralph](#getting-started-with-ralph) |

### Quality Gates

These disciplines apply regardless of which workflow you use:

- **Before claiming done**: `verification-before-completion` skill — never claim completion without running validation commands and showing output
- **When debugging**: `systematic-debugging` skill — root cause analysis before fixes
- **When writing new code**: `test-driven-development` skill — red-green-refactor
- **Standardized project checks**: `/implementation/validate` command or the `validator` subagent
- **After building**: Agent Review (Review → Find Issues) for automated code review of diffs

### Ralph: Linear-Backed Project Execution

Ralph is the right tool when you have a **well-scoped project with multiple interdependent issues** and want automated dependency ordering, status transitions, commits, and retrospectives — especially for overnight unattended execution.

**Use Ralph when:**

- You have a Linear project with 3+ sequenced implementation issues
- You want automated execution with minimal human intervention per issue
- You're running overnight and need a structured morning review

**Use the standard workflow (Brainstorm → Plan Mode → Build) when:**

- You're working on a single feature iteratively
- Scope is exploratory or requirements are still being defined
- You need tight interactive control over each step

See [Getting Started with Ralph](#getting-started-with-ralph) for setup. For post-execution triage, see the [Overnight Review Playbook](#overnight-review-playbook) in the Features section.

---

## What's Included

| Directory     | Contents                                         | Purpose                                               |
| ------------- | ------------------------------------------------ | ----------------------------------------------------- |
| `agents/`     | executor, planner, validator, reviewer, squasher, ralph-runner | Subagent definitions for plan/execute/validate/review |
| `commands/`   | implementation, git, code-review, ralph, linear  | Slash commands for Cursor workflows                   |
| `contracts/`  | ralph/core, ralph/adapters                       | Canonical workflow contracts + surface adapters       |
| `skills/`     | deployment, git, react, testing, pr-review       | On-demand skill definitions                           |
| `rules/`      | orchestrator, model selection, formatting, git   | Always-on rules for consistent AI behavior            |
| `templates/`  | AGENTS.md template, MCP example                  | Starting points for project-specific config           |
| `scripts/`    | setup.sh                                         | Installation utility                                  |

## Installation

### Quick Start (new project)

Run this from your repo root:

```bash
bash <(curl -sL https://raw.githubusercontent.com/N43-Studio/n43-cursor/main/scripts/bootstrap.sh)
```

This interactive installer will:

1. Add the `.n43-cursor` git submodule
2. Check for `GITHUB_PERSONAL_ACCESS_TOKEN` (prompt if missing)
3. Run the full setup (symlinks, MCP config, templates)
4. Verify the installation succeeded
5. Offer to commit the changes to your repo

> **wget alternative:** `bash <(wget -qO- https://raw.githubusercontent.com/N43-Studio/n43-cursor/main/scripts/bootstrap.sh)`

### Manual setup

If you prefer step-by-step control:

```bash
git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor
bash .n43-cursor/scripts/setup.sh install
```

### Pin a specific version

```bash
git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor
cd .n43-cursor && git checkout v0.0.2 && cd ..
bash .n43-cursor/scripts/setup.sh install
```

### Commit

```bash
git add .cursor/ .gitmodules .n43-cursor AGENTS.md
git commit -m "chore: add n43-cursor submodule with workspace symlinks"
```

### Devcontainer postCreateCommand

Add verify mode to your `postCreateCommand` to validate the setup on each container rebuild:

```json
"postCreateCommand": "pnpm install && git submodule update --init .n43-cursor && .n43-cursor/scripts/setup.sh"
```

The default `verify` mode checks that symlinks resolve, `mcp.json` exists, and `.cursor/.gitignore` is configured. It does not modify any files. MCP config generation only happens via `install`.

### Customize Project Context

Edit `AGENTS.md` at the repo root with your project's **non-discoverable** context. This file is project-specific and not part of the submodule.

**What belongs in AGENTS.md** (things agents cannot discover from code or config):

- Issue tracker config (platform, prefix, magic words)
- Commit scopes specific to the project
- Architectural constraints ("never import X into Y")
- Non-standard commands (only if they differ from `package.json` scripts)

**What does NOT belong** (agents discover these automatically):

- Tech stack (from `package.json`, `tsconfig.json`, framework configs)
- Directory structure (from file exploration)
- Package manager (from lockfile presence)
- Standard build/dev/test commands (from `package.json` scripts)
- Code conventions (from linter/formatter configs and existing patterns)

### Preview Changes

Use `--dry-run` to see what install would do without making changes:

```bash
bash .n43-cursor/scripts/setup.sh install --dry-run
```

### Ralph Dual-Surface Bootstrap

For Ralph workflow links across Cursor and Codex surfaces:

```bash
scripts/bootstrap-ralph-surfaces.sh install
scripts/bootstrap-ralph-surfaces.sh verify
```

This script manages:

- Cursor links in `.cursor/` for `agents`, `commands`, `rules`, and `skills`.
- Codex links in `$CODEX_HOME/skills` (or `~/.codex/skills`) for Ralph skill wrappers.

Verification output includes deterministic markers:

- `RESULT_SUMMARY ...` with checked/pass/repaired/created/failed link counts
- `RESULT PASS ...` or `RESULT FAIL ...`

### Ralph Drift Checks

Run local guardrails for cross-surface parity and terminology drift:

```bash
scripts/check-ralph-drift.sh
```

CI runs the same guardrail via `.github/workflows/ralph-drift-checks.yml`.

## Architecture

### Workspace `.cursor/` Symlinks

Cursor discovers agents, commands, skills, and rules from the workspace's `.cursor/` directory. The `install` command creates directory-level symlinks that point into `.n43-cursor/`:

```
.cursor/
├── agents -> ../.n43-cursor/agents          (directory symlink)
├── commands -> ../.n43-cursor/commands      (directory symlink)
├── rules -> ../.n43-cursor/rules            (directory symlink)
├── skills -> ../.n43-cursor/skills          (directory symlink)
├── mcp.json                                  (generated, gitignored)
├── .gitignore                                (protects mcp.json)
└── plans/                                    (project-specific)
```

Because the symlinks are committed to git, Cursor discovers them immediately — no runtime setup needed beyond ensuring the submodule is initialized.

### Shared Workflow Contracts

`contracts/ralph/` is the canonical contract layer for Ralph + Linear workflows:

- `core/` defines tool-agnostic semantics and terminology.
- `adapters/cursor/` maps Cursor commands to core contracts.
- `adapters/codex/` maps Codex skills to core contracts.

### Templates

Templates in `.n43-cursor/templates/` are processed by `setup.sh install`:

- `mcp.json.example` → `.cursor/mcp.json` (via envsubst, with `$GITHUB_PERSONAL_ACCESS_TOKEN`)
- `AGENTS.md.template` → `AGENTS.md` at repo root (copied if missing)

### Setup Modes

| Mode               | Purpose                                             | Modifies files? |
| ------------------ | --------------------------------------------------- | --------------- |
| `verify` (default) | Checks symlinks, MCP config, and .gitignore         | No              |
| `install`          | Full bootstrap: submodule, symlinks, MCP, templates | Yes             |

## Updating

Update the submodule to a newer tag:

```bash
cd .n43-cursor && git fetch && git checkout v0.1.0 && cd ..
git add .n43-cursor
git commit -m "chore: bump n43-cursor to v0.1.0"
```

Or update to the latest on main:

```bash
git submodule update --remote .n43-cursor
git add .n43-cursor
git commit -m "chore: update n43-cursor to latest"
```

## Version Pinning

The submodule pointer in git records the exact commit. Pin to tagged releases for stability. Check the [releases page](https://github.com/N43-Studio/n43-cursor/releases) for available versions.

## Features

### Multi-Agent Orchestration

Custom subagents in `agents/` are invoked by Cursor's native Plan Mode and agent system:

- **`planner`**: Creates detailed implementation plans using a 5-phase intelligence-gathering methodology
- **`executor`**: Implements code from plans step-by-step with per-task validation
- **`validator`**: Runs project health checks (lint, types, tests, build)
- **`reviewer`**: Conducts autonomous PR reviews
- **`squasher`**: Cleans up commit history before PRs
- **`ralph-runner`**: Executes one PRD issue per orchestrated Ralph loop

### Slash Commands

- `/implementation/validate` - Run all validation checks
- `/git/commit` - Create conventional commit
- `/git/squash` - Squash branch commits
- `/linear/audit-project` - Audit Linear project readiness for Ralph automation
- `/linear/create-project` - Create net-new Linear project with description + milestones
- `/linear/populate-project` - Populate existing project with issues from project context
- `/linear/generate-prd-from-project` - Generate `prd.json` from current project issues
- `/ralph/build` - Single-entry setup wrapper through audit (`create -> populate -> prd -> audit`)
- `/ralph/run` - Multi-surface Ralph loop via orchestrated subagents
- `/code-review/review-pr` - Review a pull request
- `/code-review/interactive-review` - Interactive review refinement
- `/code-review/organize-pr-for-github` - Reformat review for GitHub PR UI
- `/code-review/prepare-overnight-ralph-review` - Build morning review context from overnight Ralph artifacts

### Ralph Workflow Files

- `templates/ralph-prd.json.example` - Starter PRD schema for `/ralph/run`
- `commands/ralph/build.md` - Single-entry setup wrapper contract (`create -> populate -> prd -> audit`)
- `commands/ralph/run.md` - Orchestrator contract for multi-surface Ralph loops
- `agents/ralph-runner.md` - One-issue execution subagent
- `scripts/ralph-worktree.sh` - Deterministic `create`, `list`, and `prune` lifecycle for isolated Ralph runner worktrees

Deterministic naming defaults:

- Worktree root: `.ralph/worktrees/`
- Worktree path: `.ralph/worktrees/<issue-slug>`
- Branch: `ralph/worktree/<issue-slug>`

Examples:

```bash
scripts/ralph-worktree.sh create --issue N43-477
scripts/ralph-worktree.sh list
scripts/ralph-worktree.sh prune --issue N43-477
```

Conflict cases (for example branch already checked out elsewhere or dirty worktree removal) return explicit JSON with `status=\"conflict\"`, `conflict_reason`/`conflicts`, and escalation guidance.

### Overnight Review Playbook

- `commands/ralph/morning-briefing.md` + `scripts/generate-morning-briefing.sh` generate deterministic morning briefing markdown/JSON from `run-log.jsonl`, retrospective output, and PRD artifacts.
- `commands/code-review/prepare-overnight-ralph-review.md` + `scripts/prepare-overnight-review.sh` generate a deterministic review context doc from `progress.txt`, `run-log.jsonl`, and `.ralph/results/*-result.json`.
- `templates/code-review/overnight-ralph-review-context.md` and `templates/code-review/overnight-ralph-review-checklist.md` provide reusable review structure.

Recommended triage SLA after unattended overnight runs:

| Triage Bucket | Trigger Examples | Initial Acknowledge | Action Target |
| ------------- | ---------------- | ------------------- | ------------- |
| `critical` | security risk, data-loss path, broken execution contract | 30 minutes | mitigation plan within 2 hours |
| `high` | `human_required`, non-retryable failure, rollback uncertainty | 2 hours | owner + plan in same business day |
| `normal` | successful outcomes with skipped checks/docs drift | same business day | closure or follow-up issue within 1 business day |

Use this playbook whenever `scripts/ralph-run.sh` (or equivalent surface) produces multi-issue overnight output that requires morning human review.

### Linear Workflow Files

- `commands/linear/audit-project.md` - Audit project consistency and risk before execution
- `commands/linear/create-project.md` - Create net-new Linear projects with milestones
- `commands/linear/populate-project.md` - Generate issues for an existing project
- `commands/linear/generate-prd-from-project.md` - Export project issues to `prd.json`

Expected flow: `/linear/create-project` -> `/linear/populate-project` -> `/linear/generate-prd-from-project` -> `/ralph/run` (optional `/linear/audit-project` first).

Single-entry setup alternative: `/ralph/build` -> `/ralph/run`.

### Model Selection Guidance

Tier 1 (Opus): Deep reasoning, architecture, security
Tier 2 (Sonnet): Code implementation, following plans
Tier 3 (Fast): Procedural tasks, validation, exploration

See `rules/model-selection.mdc` for complete guidance.

## Contributing

Improvements to agents, commands, skills, or rules benefit all projects using this workflow. To contribute:

1. Test changes in a project using this workflow
2. Open a PR with clear description of the improvement
3. Update version tag after merge

## License

MIT License - See LICENSE file for details
