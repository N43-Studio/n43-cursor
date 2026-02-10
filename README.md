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

## Installation (Devcontainer)

### 1. Clone in Dockerfile

Add to your devcontainer's Dockerfile (before `USER node`):

```dockerfile
# Clone n43-cursor workflow configuration (tagged release for stability)
# To update: change the tag and rebuild the devcontainer
ARG N43_CURSOR_VERSION=v0.0.1
RUN git clone --branch ${N43_CURSOR_VERSION} --depth 1 \
      https://github.com/N43-Studio/n43-cursor.git /opt/n43-cursor \
    && rm -rf /opt/n43-cursor/.git \
    && chown -R node:node /opt/n43-cursor \
    && chmod +x /opt/n43-cursor/scripts/setup.sh
```

### 2. Create a Setup Wrapper

Create `.devcontainer/setup-cursor-workflow.sh` in your project:

```bash
#!/bin/bash
# Setup n43-cursor workflow configuration
# 1. Symlinks shared files into ~/.cursor/ (global, for all projects)
# 2. Bootstraps project-specific .cursor/ files if missing

set +e  # Don't exit on error - NEVER block container startup

N43_CURSOR_DIR="/opt/n43-cursor"

if [ ! -d "$N43_CURSOR_DIR" ]; then
    echo "n43-cursor not found at $N43_CURSOR_DIR, skipping"
    exit 0
fi

# Install shared files to ~/.cursor/
bash "$N43_CURSOR_DIR/scripts/setup.sh"

# Bootstrap project-specific files
PROJECT_CURSOR="/workspace/.cursor"

if [ ! -f "$PROJECT_CURSOR/rules/project-context.mdc" ]; then
    TEMPLATE="$N43_CURSOR_DIR/templates/project-context.mdc.template"
    if [ -f "$TEMPLATE" ]; then
        mkdir -p "$PROJECT_CURSOR/rules"
        cp "$TEMPLATE" "$PROJECT_CURSOR/rules/project-context.mdc"
        echo "Created project-context.mdc from template (customize for your project)"
    fi
fi

mkdir -p "$PROJECT_CURSOR/plans"
[ ! -f "$PROJECT_CURSOR/plans/.gitkeep" ] && touch "$PROJECT_CURSOR/plans/.gitkeep"

exit 0
```

Make it executable:

```bash
chmod +x .devcontainer/setup-cursor-workflow.sh
```

### 3. Add to postCreateCommand

In your `devcontainer.json`:

```json
"postCreateCommand": "pnpm install && .devcontainer/setup-cursor-workflow.sh"
```

### 4. Customize Project Context

Edit `.cursor/rules/project-context.mdc` with your project's tech stack, conventions, and commands.

## Architecture

### Global `~/.cursor/` vs Project `.cursor/`

Cursor reads configuration from two locations:

- **`~/.cursor/`** (global) — shared agents, commands, skills, rules, references
- **`PROJECT/.cursor/`** (project) — project-specific context, plans, MCP config

n43-cursor's `setup.sh` populates `~/.cursor/` with symlinks to `/opt/n43-cursor/`. Project-specific files stay in each project's `.cursor/` directory.

### Override Mechanism

To customize any shared file for a specific project, create a file with the same name in the project's `.cursor/` directory. Cursor's project config takes precedence over global config.

### Templates

Templates in `/opt/n43-cursor/templates/` are NOT symlinked into `~/.cursor/`. They are source files used by devcontainer setup scripts to bootstrap project config:

- `mcp.json.example` → project `.cursor/mcp.json` (via envsubst in `setup-mcp-config.sh`)
- `project-context.mdc.template` → project `.cursor/rules/project-context.mdc` (copied if missing)

## Updating

Change the `N43_CURSOR_VERSION` ARG in your Dockerfile and rebuild the devcontainer:

```dockerfile
ARG N43_CURSOR_VERSION=v1.1.0  # bump this
```

Then rebuild:

```bash
# VS Code / Cursor: "Dev Containers: Rebuild Container"
# Or manually:
docker compose -f .devcontainer/docker-compose.yml build workspace
```

## Version Pinning

Pin to a tagged release in the Dockerfile ARG for stability. Check the [releases page](https://github.com/N43-Studio/n43-cursor/releases) for available versions.

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
