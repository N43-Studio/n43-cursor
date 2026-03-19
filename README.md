# n43-cursor

Centralized Cursor IDE agent workflow configuration. Provides a consistent set of agents, commands, skills, and rules for AI-assisted development across all your projects.

## Table of Contents

- [Quick Start](#quick-start)
- [Suggested Developer Workflow](#suggested-developer-workflow)
- [Installation](#installation)
- [Ralph](#ralph)
- [What's Included](#whats-included)
- [Architecture](#architecture)
- [Updating](#updating)
- [Contributing](#contributing)

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/N43-Studio/n43-cursor/main/scripts/bootstrap.sh)
```

The interactive installer adds the submodule, creates symlinks, generates MCP config, verifies the setup, and offers to commit. It requires `git`, `curl`, and `envsubst` (from `gettext` — pre-installed on most systems; `brew install gettext` on macOS if missing).

> **wget alternative:** `bash <(wget -qO- https://raw.githubusercontent.com/N43-Studio/n43-cursor/main/scripts/bootstrap.sh)`

After installation, reload Cursor to pick up the new agents, rules, skills, and commands.

## Suggested Developer Workflow

### Feature Development: Brainstorm → Plan → Build

1. **Brainstorm** — The `superpowers/brainstorming` skill triggers automatically on creative work. It walks through clarifying requirements one question at a time, proposes 2–3 approaches with trade-offs, and gates on design approval before any code is written.

2. **Plan Mode** — Press **Shift+Tab** to enter Plan Mode. The agent researches your codebase, generates a structured plan with file paths and code references, and lets you edit it as markdown before building.

3. **Build** — Click **Build** to execute the plan. If the result drifts from intent, revert and refine the plan rather than patching with follow-ups.

4. **Iterate** — For complex features, save the plan to workspace (`.cursor/plans/`) for cross-session continuity.

| Situation | Approach |
| --------- | -------- |
| Quick fix, routine change | Agent Mode directly |
| New feature or unclear scope | Brainstorm → Plan Mode → Build |
| Multi-system / architectural change | Brainstorm → Plan Mode → Build, save plan to workspace |
| Well-scoped project with multiple issues | [Ralph](#ralph) |

### Quality Gates

These apply regardless of workflow:

- **Before claiming done** — `verification-before-completion` skill: run validation commands and show output
- **When debugging** — `systematic-debugging` skill: root cause analysis before fixes
- **When writing new code** — `test-driven-development` skill: red-green-refactor
- **Project health checks** — `/implementation/validate` command or the `validator` subagent
- **After building** — Agent Review (Review → Find Issues) for automated code review

### When to Use Ralph

Ralph is the right tool when you have a **well-scoped project with multiple interdependent issues** and want automated dependency ordering, status transitions, commits, and retrospectives — especially for overnight unattended execution. See the [Ralph section](#ralph) below for setup.

## Installation

### Manual setup

If you prefer step-by-step control over the [one-liner bootstrap](#quick-start):

```bash
git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor
bash .n43-cursor/scripts/setup.sh install

git add .cursor/ .gitmodules .n43-cursor AGENTS.md
git commit -m "chore: add n43-cursor submodule with workspace symlinks"
```

### Pin a specific version

```bash
git submodule add https://github.com/N43-Studio/n43-cursor.git .n43-cursor
cd .n43-cursor && git checkout v0.0.2 && cd ..
bash .n43-cursor/scripts/setup.sh install
```

### Preview changes

```bash
bash .n43-cursor/scripts/setup.sh install --dry-run
```

### Devcontainer

Add verify mode to `postCreateCommand` to validate on each container rebuild:

```json
"postCreateCommand": "pnpm install && git submodule update --init .n43-cursor && .n43-cursor/scripts/setup.sh"
```

The default `verify` mode checks symlinks, `mcp.json`, and `.gitignore` without modifying files.

### GitHub MCP Integration (optional)

Set `GITHUB_PERSONAL_ACCESS_TOKEN` in your environment before running install to enable the GitHub MCP server in Cursor. If skipped during bootstrap, re-run:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...
bash .n43-cursor/scripts/setup.sh install
```

### Customize Project Context

Edit `AGENTS.md` at the repo root with your project's **non-discoverable** context:

**What belongs in AGENTS.md:**
- Issue tracker config (platform, prefix, magic words)
- Commit scopes specific to the project
- Architectural constraints ("never import X into Y")
- Non-standard commands (only if they differ from `package.json` scripts)

**What does NOT belong** (agents discover these automatically):
- Tech stack, directory structure, package manager, standard build/test commands, code conventions

## Ralph

Ralph takes a Linear project and executes its issues one-by-one through AI agents, handling dependency ordering, status transitions, commits, and retrospectives.

### Prerequisites (Ralph only)

Terminal-based Ralph execution requires additional tools beyond the base install:

| Tool | Required For | Install |
| ---- | ------------ | ------- |
| [Node.js](https://nodejs.org/) 18+ | Script runtime | `brew install node` or [nvm](https://github.com/nvm-sh/nvm) |
| [jq](https://jqlang.github.io/jq/) | JSON processing in Ralph scripts | `brew install jq` |
| [Codex CLI](https://github.com/openai/codex) | Terminal execution backend | `npm install -g @openai/codex` |

> These are only needed for `scripts/ralph-run.sh` (terminal surface). The Cursor `/ralph/run` command works entirely within Cursor's agent system and does not need them.

### Fast path

```
/ralph/build    # create project → populate issues → generate PRD → audit
/ralph/run      # execute issues one-by-one
```

### Manual path

```
/linear/create-project              # define project + milestones
/linear/populate-project            # generate issues from scope
/linear/generate-prd-from-project   # export to prd.json
/linear/audit-project               # validate readiness (recommended)
/ralph/run prd=.cursor/ralph/<project-slug>/prd.current.json
```

### Issue requirements

Every issue Ralph executes needs four sections: `## Goal`, `## Context`, `## Acceptance Criteria`, and `## Validation`. The `/linear/populate-project` command generates issues in this format automatically.

> For detailed Ralph reference — execution backends, worktree management, overnight review playbook, triage SLAs, dual-surface bootstrap, and drift checks — see [docs/ralph.md](docs/ralph.md). For the underlying package architecture, see the [ralph repo](https://github.com/N43-Studio/ralph).

## What's Included

| Directory | Contents | Purpose |
| --------- | -------- | ------- |
| `agents/` | planner, executor, validator, reviewer, squasher, ralph-runner | Custom subagents for Cursor's native agent system |
| `commands/` | implementation, git, code-review, ralph, linear, project-closeout | Slash commands for Cursor workflows |
| `contracts/` | ralph/core, ralph/adapters | Canonical workflow contracts + surface adapters |
| `skills/` | deployment, git, react, testing, pr-review | On-demand skill definitions |
| `rules/` | orchestrator, model selection, formatting, git | Always-on rules for consistent AI behavior |
| `templates/` | AGENTS.md template, MCP example | Starting points for project-specific config |
| `scripts/` | setup.sh, bootstrap.sh, ralph-run.sh | Installation and runtime utilities |
| `docs/` | ralph.md | Detailed reference documentation |

### Subagents

| Agent | Purpose | Model |
| ----- | ------- | ----- |
| `planner` | 5-phase codebase analysis and plan generation | Tier 1 (Opus) |
| `executor` | Step-by-step plan implementation with per-task validation | Tier 2 (Sonnet) |
| `validator` | Project health checks (lint, types, tests, build) | Tier 3 (Fast) |
| `reviewer` | Autonomous PR code reviews | Tier 1 (Opus) |
| `squasher` | Commit history cleanup before PRs | Tier 2 (Sonnet) |
| `ralph-runner` | Single-issue execution in orchestrated Ralph loops | Tier 2 (Sonnet) |

### Slash Commands

| Command | Purpose |
| ------- | ------- |
| `/implementation/validate` | Run all project validation checks |
| `/git/commit` | Create conventional commits with Linear integration |
| `/git/squash` | Squash branch commits for PR readiness |
| `/ralph/build` | Single-entry project setup through audit |
| `/ralph/run` | Execute Ralph loop via orchestrated subagents |
| `/linear/create-project` | Create a new Linear project with milestones |
| `/linear/populate-project` | Generate issues from project scope |
| `/linear/generate-prd-from-project` | Export project issues to `prd.json` |
| `/linear/audit-project` | Audit project readiness for Ralph |
| `/code-review/review-pr` | Generate a PR review document |
| `/code-review/interactive-review` | Refine a review interactively |

See `rules/model-selection.mdc` for recommended model tiers per command.

## Architecture

### Symlink Structure

`setup.sh install` creates directory-level symlinks from `.cursor/` into `.n43-cursor/`:

```
.cursor/
├── agents    → ../.n43-cursor/agents
├── commands  → ../.n43-cursor/commands
├── rules     → ../.n43-cursor/rules
├── skills    → ../.n43-cursor/skills
├── mcp.json  (generated, gitignored)
├── .gitignore
└── plans/    (project-specific)
```

Symlinks are committed to git, so Cursor discovers everything immediately with no runtime setup.

### Workflow Contracts

`contracts/ralph/` is the canonical contract layer:
- `core/` — tool-agnostic semantics and terminology
- `adapters/cursor/` — maps Cursor commands to core contracts
- `adapters/codex/` — maps Codex skills to core contracts

### Templates

Processed by `setup.sh install`:
- `mcp.json.example` → `.cursor/mcp.json` (via envsubst with `$GITHUB_PERSONAL_ACCESS_TOKEN`)
- `AGENTS.md.template` → `AGENTS.md` at repo root (copied if missing)

## Updating

```bash
# Update to a tagged release
cd .n43-cursor && git fetch && git checkout v0.1.0 && cd ..
git add .n43-cursor
git commit -m "chore: bump n43-cursor to v0.1.0"

# Or update to latest on main
git submodule update --remote .n43-cursor
git add .n43-cursor
git commit -m "chore: update n43-cursor to latest"
```

Pin to tagged releases for stability. The submodule pointer records the exact commit. Check the [releases page](https://github.com/N43-Studio/n43-cursor/releases) for available versions.

## Contributing

Improvements to agents, commands, skills, or rules benefit all projects using this workflow:

1. Test changes in a project using this workflow
2. Open a PR with clear description of the improvement
3. Update version tag after merge

## License

MIT License — see LICENSE file for details.
