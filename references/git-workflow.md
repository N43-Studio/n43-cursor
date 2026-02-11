# Git Workflow Reference

A comprehensive guide to git workflow and commit conventions.

---

## Table of Contents

1. [Branch Workflow](#1-branch-workflow)
2. [Conventional Commits](#2-conventional-commits)
3. [Pull Request Process](#3-pull-request-process)
4. [Issue Tracker Integration](#4-issue-tracker-integration)
5. [Code Review Guidelines](#5-code-review-guidelines)

---

## 1. Branch Workflow

### Starting Work

1. Assign the issue in your issue tracker and mark as "In Progress"
2. Ensure your local `main` is up-to-date
3. Create branch using consistent naming format

### Branch Naming

Standard branch format:

```
<username>/<issue-id>-<issue-title-slug>
```

**Best Practices**:

- Use **first name only** for username (e.g., "ryan" not "ryankilroy")
- Keep slug to **max 30 characters**
- Use action verb + key noun (e.g., "add-user-auth", "fix-login-redirect")
- Drop filler words: "with", "and", "the", "for"

**Preferred Example**:

```bash
git checkout -b ryan/{prefix}-149-add-agentic-context
```

**Avoid** (too long):

```bash
git checkout -b ryankilroy/{prefix}-149-mvp-attempt-to-use-entirely-agentic-context-management
```

### Keeping Up to Date

```bash
# Update main
git checkout main
git pull origin main

# Rebase feature branch
git checkout feature-branch
git rebase main
```

---

## 2. Conventional Commits

All commits MUST follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type       | When to Use                                         |
| ---------- | --------------------------------------------------- |
| `feat`     | New feature for users                               |
| `fix`      | Bug fix for users                                   |
| `docs`     | Documentation only changes                          |
| `style`    | Formatting, missing semicolons, etc.                |
| `refactor` | Code change that neither fixes bug nor adds feature |
| `perf`     | Performance improvement                             |
| `test`     | Adding or correcting tests                          |
| `chore`    | Maintenance tasks, dependencies                     |
| `build`    | Build system or external dependencies               |
| `ci`       | CI configuration changes                            |

### Scopes (Project-Specific)

Define in your `project-context.mdc`. Common examples:

| Scope    | Description                                    |
| -------- | ---------------------------------------------- |
| `api`    | Backend API changes                            |
| `ui`     | Frontend UI changes                            |
| `db`     | Database changes                               |
| `auth`   | Authentication                                 |
| `build`  | Build configuration                            |
| `cursor` | Cursor/agent workflow (commands, rules, plans) |

### Docs vs Agentic Workflow

Use the `cursor` scope to differentiate agentic workflow changes from traditional documentation:

| Change Type           | Commit Format    | Examples                              |
| --------------------- | ---------------- | ------------------------------------- |
| Traditional docs      | `docs:`          | README, API docs, code comments       |
| Cursor commands/rules | `chore(cursor):` | `.cursor/commands/`, `.cursor/rules/` |
| Cursor references     | `docs(cursor):`  | `.cursor/references/`                 |
| Agent plans           | `chore(cursor):` | `.cursor/plans/`                      |

```bash
# Traditional documentation
docs: update README with setup instructions

# Cursor command or rule (tooling)
chore(cursor): add commit command for conventional commits

# Cursor reference documentation
docs(cursor): add git workflow reference

# Agent planning files
chore(cursor): add feature plan for authentication
```

### Breaking Changes

Use `!` after type/scope to indicate breaking change:

```
feat(api)!: change authentication endpoint response format
```

### Examples

**Bad:**

```
Reconfigured whosit logic in the foobar.ts, helloworld.ts, and buzzbangbap.ts api files. Also added new functionality to the startup script which requires a new env var
```

**Good:**

```
refactor(api): modify whosit logic to handle special characters
```

```
feat(build)!: enable telemetry via new required env var

- You need to provide a TELEMETRY_API_KEY in your .env file from now on to use the startup script
```

**More Examples:**

```bash
# Feature
feat(ui): add dark mode toggle to settings panel

# Bug fix
fix(api): handle null values in user profile endpoint

# Refactor
refactor(auth): extract token validation to middleware

# Documentation
docs: update API endpoint documentation

# Breaking change
feat(api)!: change response format for /api/users endpoint

BREAKING CHANGE: Response now returns { data: [...] } instead of direct array
```

---

## 3. Pull Request Process

### Before Opening PR

1. Squash commits into logical chunks
2. Keep PRs small and focused (easier to review)
3. Update branch with latest `main` via rebase
4. Ensure all tests pass

### Opening PR

1. Open PR from `feature-branch` to `main`
2. Fill out PR template
3. Link issue from your issue tracker

### After Approval

**REBASE, don't merge:**

```bash
git checkout feature-branch
git rebase main
git push --force-with-lease
```

> **Why `--force-with-lease`?** It's safer than `--force` because it will fail if someone else pushed to the branch.

### Golden Rule

Never rebase `main`. Only rebase feature branches.

---

## 4. Issue Tracker Integration

### Common Issue Tracker Status Flows

#### Linear

| Status       | Description                            |
| ------------ | -------------------------------------- |
| Triage       | Issues from external sources to review |
| Backlog      | Default landing spot (drafts)          |
| Todo         | Ready to be picked up                  |
| In Progress  | Actively being worked on               |
| Needs Review | PR open, waiting for reviewer          |
| In Review    | Reviewer actively reviewing            |
| Reviewed     | PR approved, ready to merge            |
| Ready for QA | Code on staging for testing            |
| Done         | Deployed to production                 |

#### Jira / GitHub Projects

Similar statuses - configure in your `project-context.mdc`.

### Linking Issues in Commits

Most issue trackers support **magic words** that automatically link commits/PRs to issues and update issue status.

#### Magic Words

| Keyword    | Variants          | Effect on Merge     |
| ---------- | ----------------- | ------------------- |
| `Closes`   | close, closed     | Marks issue as Done |
| `Fixes`    | fix, fixed        | Marks issue as Done |
| `Resolves` | resolve, resolved | Marks issue as Done |

#### Syntax

Use magic word + issue ID in commit message or PR description:

```
feat(api): add user profile endpoint

Implements user profile fetching with avatar support.

Closes {PREFIX}-123
```

Examples for different trackers:

- Linear: `Closes N43-123`
- Jira: `Closes PROJ-456`
- GitHub Issues: `Closes #789`

#### Automatic Status Updates

When commit linking is enabled:

- **Branch pushed** → Issue moves to "In Progress"
- **PR opened** → Issue moves to "Needs Review"
- **PR merged to main** → Issue moves to "Done" (if magic word used)

#### Multiple Issues

Link multiple issues in one commit:

```
fix(api): resolve authentication edge cases

Fixes {PREFIX}-123
Fixes {PREFIX}-124
```

#### Reference Without Closing

Use `Refs` to link without closing:

```
refactor(auth): extract token validation

Refs {PREFIX}-125
```

---

## 5. Code Review Guidelines

### Comment Prefixes

| Prefix      | Meaning                     | Blocking? |
| ----------- | --------------------------- | --------- |
| `major:`    | Blocks PR approval          | Yes       |
| `minor:`    | Should change, non-blocking | No        |
| `nit:`      | Tiny improvement, non-issue | No        |
| `question:` | Seeking clarification       | No        |
| `praise:`   | Positive feedback           | No        |

> **Note:** `praise:` is underutilized. Recognize good decisions!

### Language Guidelines

- Use "we", "I", or "code" instead of "you"
- Be specific in suggestions
- Link issues for temporary code

### Example

**Bad:**

> "You should test this input"

**Good:**

> "minor: This code needs to check that it is a valid input (i.e., a valid email address)"

For temporary fixes:

```typescript
// TODO: Validate user input - [{PREFIX}-123: Validate email input against a regex]
const userEmail: string = textField.value
```

---

## Quick Reference

### Commit Message Template

```
<type>(<scope>): <description>

[body]

[Closes {PREFIX}-XXX]
```

### Common Commands

```bash
# Start work on issue
git checkout main
git pull origin main
git checkout -b <branch-name>

# Commit changes
git add -A
git commit -m "feat(scope): description"

# Update from main
git fetch origin
git rebase origin/main

# Push (after rebase)
git push --force-with-lease

# Squash commits
git rebase -i HEAD~<n>
```

### PR Review Checklist

- [ ] Code follows project conventions
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No console.logs or debug code
- [ ] Types are correct
- [ ] Error handling is appropriate

---

## Resources

- [Conventional Commits Spec](https://www.conventionalcommits.org/en/v1.0.0/)
- [Merging vs Rebasing](https://www.atlassian.com/git/tutorials/merging-vs-rebasing)
- [Force with Lease Explained](https://stackoverflow.com/a/52823955)
