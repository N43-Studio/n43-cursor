# n43-cursor

Centralized Cursor IDE agent workflow configuration. Provides a consistent set of agents, commands, skills, rules, and references for AI-assisted development across all your projects.

## What's Included

| Directory     | Contents                                         | Purpose                                               |
| ------------- | ------------------------------------------------ | ----------------------------------------------------- |
| `agents/`     | executor, planner, validator, reviewer, squasher | Subagent definitions for plan/execute/validate/review |
| `commands/`   | implementation, git, code-review                 | Slash commands for Cursor workflows                   |
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

### Templates

Templates in `.n43-cursor/templates/` are processed by `setup.sh install`:

- `mcp.json.example` → `.cursor/mcp.json` (via envsubst, with `$GITHUB_PERSONAL_ACCESS_TOKEN`)
- `project-context.mdc.template` → `AGENTS.md` at repo root (copied if missing)

### Setup Modes

| Mode | Purpose | Modifies files? |
|------|---------|----------------|
| `verify` (default) | Checks symlinks, MCP config, and .gitignore | No |
| `install` | Full bootstrap: submodule, symlinks, MCP, templates | Yes |

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

### Slash Commands

- `/implementation/plan-feature` - Create implementation plan
- `/implementation/execute` - Execute a plan
- `/implementation/implement` - Orchestrated plan + execute cycle
- `/implementation/validate` - Run all validation checks
- `/git/commit` - Create conventional commit
- `/git/squash` - Squash branch commits
- `/code-review/review-pr` - Review a pull request
- `/code-review/interactive-review` - Interactive review refinement
- `/code-review/organize-pr-for-github` - Reformat review for GitHub PR UI

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
