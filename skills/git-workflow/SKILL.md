---
name: git-workflow
description: Provides git workflow conventions including conventional commits, branch naming, PR review guidelines, and issue tracker integration. Use when performing git operations, creating commits, opening PRs, conducting code reviews, or managing branches.
---

# Git Workflow Conventions

## Quick Start

### Commit Format

All commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`

**Scopes**: Define project-specific scopes in `AGENTS.md`. Common examples: `api`, `ui`, `db`, `auth`, `build`, `cursor`

**Agentic workflow commits**: Use `chore(cursor):` for commands/rules/plans, `docs(cursor):` for reference docs.

### Branch Naming

Default model: personal dev branch (e.g., `ryan`, `erik`).

- Feature branches are optional for exceptional isolation needs.
- Issue association is done through commit footer links, not branch naming.

### PR Review Prefixes

| Prefix        | Meaning           | Blocking |
| ------------- | ----------------- | -------- |
| `major:`      | Must fix          | Yes      |
| `minor:`      | Should fix        | No       |
| `nit:`        | Tiny improvement  | No       |
| `suggestion:` | Loose idea        | No       |
| `question:`   | Clarification     | No       |
| `praise:`     | Positive feedback | No       |

Use "we"/"the code" instead of "you" in review comments.

### Issue Tracker Integration

Configure your issue tracker in `AGENTS.md`:

- Magic words auto-close on merge: `Closes {PREFIX}-XXX`, `Fixes {PREFIX}-XXX`, `Resolves {PREFIX}-XXX`
- Link without closing: `Refs {PREFIX}-XXX`

Examples:

- Linear: branch `ryan`, footer `Closes N43-123`
- Jira: branch `erik`, footer `Closes PROJ-456`
- GitHub: branch `ryan`, footer `Closes #789`

### PR Workflow

1. Squash commits into logical chunks
2. Rebase onto `main` (never merge)
3. Use `--force-with-lease` when pushing after rebase

## Additional Resources

- For complete documentation, see [reference.md](reference.md)
