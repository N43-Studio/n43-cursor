# n43-cursor

Centralized Cursor IDE agent workflow configuration. Provides a consistent set of agents, commands, skills, rules, and references for AI-assisted development across all your projects.

## What's Included

| Directory     | Contents                                         | Purpose                                               |
| ------------- | ------------------------------------------------ | ----------------------------------------------------- |
| `agents/`     | executor, planner, validator, reviewer, squasher, ralph-runner | Subagent definitions for plan/execute/validate/review |
| `commands/`   | implementation, git, code-review, ralph, linear  | Slash commands for Cursor workflows                   |
| `contracts/`  | ralph/core, ralph/adapters                       | Canonical workflow contracts + surface adapters       |
| `skills/`     | deployment, git, react, testing, pr-review       | On-demand skill definitions                           |
| `rules/`      | orchestrator, model selection, formatting, git   | Always-on rules for consistent AI behavior            |
| `references/` | deployment, git, react, testing                  | Reference docs for best practices                     |
| `templates/`  | project context template, MCP example            | Starting points for project-specific config           |
| `scripts/`    | setup.sh                                         | Installation utility                                  |

## Installation

### Quick Start (new project)

Run a single command from your repo root:

```bash
bash .n43-cursor/scripts/setup.sh install
```

This will:

- Add the `.n43-cursor` git submodule (if not already present)
- Create the `.cursor/` directory
- Create directory-level symlinks (agents, commands, references, skills, rules)
- Generate MCP config from template (using `$GITHUB_PERSONAL_ACCESS_TOKEN` if set)
- Create `.cursor/.gitignore` to protect generated secrets (`mcp.json`)
- Copy project-context template to `AGENTS.md` (if missing)

### Or add the submodule first, then install

If you want to pin a specific version:

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

Edit `AGENTS.md` at the repo root with your project's tech stack, conventions, and commands. This file is project-specific and not part of the submodule.

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

- Cursor links in `.cursor/` for `agents`, `commands`, `references`, `rules`, and `skills`.
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

Cursor discovers agents, commands, skills, rules, and references from the workspace's `.cursor/` directory. The `install` command creates directory-level symlinks that point into `.n43-cursor/`:

```
.cursor/
├── agents -> ../.n43-cursor/agents          (directory symlink)
├── commands -> ../.n43-cursor/commands      (directory symlink)
├── references -> ../.n43-cursor/references  (directory symlink)
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

- **Planning Agent**: Creates detailed implementation plans
- **Execution Agent**: Implements code following plans
- **Validation Agent**: Runs tests and checks
- **Review Agent**: Conducts autonomous PR reviews
- **Squash Agent**: Cleans up commit history
- **Ralph Runner Agent**: Executes one PRD issue per orchestrated loop

### Slash Commands

- `/implementation/plan-feature` - Create implementation plan
- `/implementation/execute` - Execute a plan
- `/implementation/implement` - Orchestrated plan + execute cycle
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
- `/code-review/generate-morning-briefing` - Generate deterministic morning briefing markdown + JSON from overnight artifacts
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

- `commands/code-review/generate-morning-briefing.md` + `scripts/generate-morning-briefing.sh` generate deterministic morning briefing markdown/JSON from `run-log.jsonl`, retrospective output, and review-queue artifacts.
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
