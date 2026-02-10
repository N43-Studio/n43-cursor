> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

> **Why**: Change analysis, commit message crafting, Linear integration

# Commit

Create a properly formatted git commit with intelligent Linear issue management.

## Reference

Read `.cursor/references/git-workflow.md` for full commit conventions.

## Quick Path (Normal Commit)

The [Branch Guard](#0-branch-guard) always runs first. If that passes and you're confident changes belong to the current branch, jump to [Standard Commit Flow](#4-standard-commit-flow).

---

## Full Process

### 0. Branch Guard

Before any commit operations, verify the current branch:

```bash
git branch --show-current
```

**If on `main`**: STOP immediately. Do not commit.

```
🚫 Cannot commit directly to main

Direct commits to main are not allowed. You must be on a feature branch
with an associated Linear issue.

Options:
A) Create a new Linear issue and feature branch for this work
B) Switch to an existing feature branch
C) Cancel
```

- If user selects **A**, proceed to [Create Linear Issue](#3-create-linear-issue-option-a).
- If user selects **B**, ask which branch and run `git checkout <branch>`, then restart from Step 0.
- If user selects **C**, exit gracefully.

**If branch name does not contain a Linear issue ID** (no match for `[nN]43-\d+`): STOP.

```
⚠️ No Linear issue associated with this branch

Branch: <current-branch-name>
Expected format: <username>/<issue-id>-<slug> (e.g., ryan/n43-149-add-user-auth)

Every feature branch must be linked to a Linear issue.

Options:
A) Create a new Linear issue and feature branch for this work (recommended)
B) Cancel
```

- If user selects **A**, proceed to [Create Linear Issue](#3-create-linear-issue-option-a).
- If user selects **B**, exit gracefully.

**If on a valid feature branch with a Linear issue ID**: Continue to [Analyze Changes](#1-analyze-changes).

---

### 1. Analyze Changes

Run these commands to understand what's being committed:

```bash
# View staged changes
git diff --cached --stat

# View detailed changes
git diff --cached
```

### 1b. Extract Linear Issue

The branch guard (Step 0) guarantees a Linear issue ID is present. Extract it from the branch name using pattern `[nN]43-\d+`:

```bash
# Example: erik/n43-149-some-feature → N43-149
```

Fetch issue details:

- Use Linear MCP `get_issue` tool with the extracted issue ID
- Capture: title, description, labels

```
CallMcpTool: project-0-workspace-Linear / get_issue
Arguments: { "id": "N43-149" }
```

**Error Handling**: If Linear MCP call fails:

1. Do NOT silently fall back to standard commit
2. Ask the user:
   - **Option A**: Reconnect/reauth to Linear first (user can fix MCP connection)
   - **Option B**: Proceed without Linear integration (standard commit flow)
3. If user selects A, provide guidance:
   - Check MCP server status
   - Verify Linear authentication
   - Restart MCP connection if needed
4. If user selects B, skip to [Standard Commit Flow](#4-standard-commit-flow)

### 1c. Assess Work Relevance

Evaluate whether staged changes relate to the branch's Linear issue:

**Relevance Signals**:

| Signal             | Weight | Check                                               |
| ------------------ | ------ | --------------------------------------------------- |
| File scope matches | High   | Do changed files' scopes align with issue domain?   |
| Keywords overlap   | Medium | Do file names/paths contain issue title words?      |
| Change type fits   | Low    | Does the change type (feat/fix/refactor) fit issue? |

**Domain Scope Mapping**:

| Path Pattern                 | Domain      | Linear Label           |
| ---------------------------- | ----------- | ---------------------- |
| `backend/`                   | Backend     | "Domain → Backend"     |
| `frontend/`                  | Frontend    | "Domain → Frontend"    |
| `agents/`                    | Agents      | "Domain → Agents"      |
| `docker/`, `scripts/`        | DevOps      | "Domain → DevOps"      |
| `.cursor/`, `.devcontainer/` | Dev Tooling | "Domain → Dev Tooling" |

**Special Case**: `.cursor/` and `.devcontainer/` changes should be flagged as potentially unrelated unless the current issue specifically mentions tooling/DX work.

**Decision**:

- If changes appear **related**: Continue with [Standard Commit Flow](#4-standard-commit-flow)
- If changes appear **unrelated**: Proceed to [Smart Branching Decision](#2-smart-branching-decision-when-work-diverges)

---

## 2. Smart Branching Decision (When Work Diverges)

If staged changes don't relate to current branch's Linear issue, present options:

### Assessment Presentation

```
⚠️ Staged changes may not relate to current issue

Current Branch: erik/n43-149-add-user-auth
Current Issue: N43-149 - Add user authentication
Changed Files:
  - .cursor/commands/git/commit.md
  - .cursor/references/git-workflow.md

These changes appear to be Dev Tooling work, not Authentication work.
```

### User Options

| Option | Action                                           |
| ------ | ------------------------------------------------ |
| **A**  | Create new Linear issue and branch (recommended) |
| **B**  | Commit to current branch anyway                  |
| **C**  | Cancel - I'll handle this manually               |

If user selects **A**, proceed to [Create Linear Issue](#3-create-linear-issue-option-a).
If user selects **B**, continue with [Standard Commit Flow](#4-standard-commit-flow).
If user selects **C**, exit gracefully.

---

## 3. Create Linear Issue (Option A)

### Step 1: Generate Issue Title

Based on staged changes, suggest a title:

- Summarize the nature of changes (e.g., "Enhance commit command with Linear integration")
- Keep under 80 characters
- Ask user to confirm or modify

### Step 2: Determine Labels

**Domain Label** (auto-detected from file paths):

| Path Pattern                 | Label                  |
| ---------------------------- | ---------------------- |
| `backend/`                   | "Domain → Backend"     |
| `frontend/`                  | "Domain → Frontend"    |
| `agents/`                    | "Domain → Agents"      |
| `docker/`, `scripts/`        | "Domain → DevOps"      |
| `.cursor/`, `.devcontainer/` | "Domain → Dev Tooling" |

**Issue Type Label** (from inferred commit type):

| Commit Type | Label                      |
| ----------- | -------------------------- |
| `feat`      | "Issue Type → Feature"     |
| `fix`       | "Issue Type → Bug"         |
| Other       | "Issue Type → Improvement" |

### Step 3: Create the Issue

Use Linear MCP with hardcoded configuration:

```
CallMcpTool: project-0-workspace-Linear / create_issue
Arguments: {
  "title": "<user-confirmed-title>",
  "team": "Studio",
  "state": "In Progress",
  "assignee": "me",
  "priority": 3,
  "labels": ["<domain-label>", "<issue-type-label>"]
}
```

Capture the created issue's ID from response.

### Step 4: Determine Branch Point

**Ask the user** which strategy to use:

#### Option 1: Branch from `main` (Independent work)

Choose this when:

- Changes don't depend on uncommitted work in current branch
- Adding new functionality that stands alone
- Documentation or tooling changes

```bash
# Stash staged changes
git stash push -m "smart-branch: changes for new issue"

# Update and branch from main
git checkout main
git pull origin main
git checkout -b <new-branch-name>

# Restore changes
git stash pop
```

#### Option 2: Branch from current HEAD (Dependent work)

Choose this when:

- Changes build on uncommitted modifications in current branch
- Extracting/refactoring code that was just changed
- Work is sequential with current branch

```bash
# Simply create branch from current position
git checkout -b <new-branch-name>
```

### Step 5: Create Branch

Get username from Linear (preferred) or git config:

```
# Option 1: From Linear (preferred - uses first name)
CallMcpTool: project-0-workspace-Linear / get_user
Arguments: { "query": "me" }
# Returns: { "name": "Ryan Kilroy", ... }
# Extract first name: "Ryan" → "ryan"

# Option 2: Fallback to git config
git config user.name
# "Ryan Kilroy" → extract first name → "ryan"
```

**Branch Name Format**: `<firstname>/<issue-id>-<short-slug>`

**Slug Guidelines** (keep it SHORT):

- Max 30 characters
- Use action verb + key noun (e.g., "add-linear-commit", "fix-auth-redirect")
- Drop filler words: "with", "and", "the", "for", "to", "in"
- Drop redundant context (issue title already has detail)
- Prefer: `add-X`, `fix-X`, `update-X`, `remove-X`

**Examples**:

| Issue Title                                            | Good Slug              | Bad Slug                                               |
| ------------------------------------------------------ | ---------------------- | ------------------------------------------------------ |
| "Enhance commit command with smart Linear integration" | `add-linear-commit`    | `enhance-commit-command-with-smart-linear-integration` |
| "Fix authentication redirect on logout"                | `fix-auth-redirect`    | `fix-authentication-redirect-on-logout`                |
| "Add user profile settings page"                       | `add-profile-settings` | `add-user-profile-settings-page`                       |

**Full Example**: `ryan/n43-201-add-linear-commit`

After branch creation, proceed to [Standard Commit Flow](#4-standard-commit-flow).

---

## 4. Standard Commit Flow

### 4a. Determine Commit Type

Based on the changes, select the appropriate type:

| Type       | Use When                                   |
| ---------- | ------------------------------------------ |
| `feat`     | Adding new functionality                   |
| `fix`      | Fixing a bug                               |
| `docs`     | Documentation only                         |
| `style`    | Formatting changes                         |
| `refactor` | Code restructuring without behavior change |
| `perf`     | Performance improvements                   |
| `test`     | Adding or updating tests                   |
| `chore`    | Maintenance, dependencies                  |
| `build`    | Build system changes                       |
| `ci`       | CI/CD changes                              |

### 4b. Determine Scope

Use these project scopes:

- `api` - Backend API changes
- `ui` - Frontend UI changes
- `db` - Database changes
- `auth` - Authentication
- `build` - Build configuration
- `cursor` - Cursor/agent workflow files
- Or omit for broad changes

**Docs vs Agentic Workflow:**

- `docs:` - Traditional documentation (README, API docs)
- `chore(cursor):` - Cursor commands, rules, agent plans
- `docs(cursor):` - Cursor reference documentation

### 4c. Check for Breaking Changes

If the change breaks backward compatibility:

- Add `!` after type/scope: `feat(api)!:`
- Add `BREAKING CHANGE:` footer explaining the impact

### 4d. Extract Linear Issue

If branch name contains issue ID (e.g., `n43-149`):

- Use a **magic word** to auto-close on merge: `Closes`, `Fixes`, or `Resolves`
- Use `Refs N43-XXX` to link without closing
- Multiple issues: add each on its own line

### 4e. Format Commit Message

```
<type>(<scope>): <short description in imperative mood>

[Optional longer description explaining what and why]

[Closes N43-XXX]
[BREAKING CHANGE: description if applicable]
```

### 4f. Create Commit

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<body if needed>

<footer>
EOF
)"
```

---

## Edge Cases & Error Handling

### No Linear Issue in Branch Name

This is now enforced by the [Branch Guard](#0-branch-guard) (Step 0). If the branch doesn't contain a Linear issue ID matching `[nN]43-\d+`, the commit process stops and guides the user to create a Linear issue and properly named feature branch before proceeding.

### Linear MCP Unavailable

**IMPORTANT**: Do NOT silently fall back to standard commit.

If MCP calls fail (connection error, auth expired, etc.):

1. **Stop and inform the user**:

   ```
   ⚠️ Unable to connect to Linear MCP

   Error: <error message>
   ```

2. **Offer options**:

   | Option | Action                             |
   | ------ | ---------------------------------- |
   | **A**  | Reconnect/reauth to Linear first   |
   | **B**  | Proceed without Linear integration |

3. **If user selects A**, provide guidance:
   - Check MCP server status
   - Verify Linear authentication
   - Restart MCP connection if needed

4. **If user selects B**, continue with standard commit flow

### User Has Unstaged Changes

If `git status` shows unstaged changes alongside staged:

- Warn user before branching operations
- Stash commands may affect more than intended
- Recommend: "Commit or stash other changes first"

### Branch Already Exists

If target branch name already exists:

- Offer to checkout existing branch and commit there
- Or append timestamp suffix: `<branch-name>-20260204-1430`

### Ambiguous Scope Detection

If changes span multiple scopes (e.g., backend/ AND frontend/):

- Use primary scope (most changed files) for Domain label
- Or allow multiple Domain labels

---

## Examples

### Simple Feature

```bash
git commit -m "feat(ui): add dark mode toggle to settings"
```

### Feature with Body

```bash
git commit -m "$(cat <<'EOF'
feat(api): add user profile endpoint

Implements GET /api/users/:id/profile with:
- Avatar URL resolution
- Cached response headers
- Rate limiting

Closes N43-142
EOF
)"
```

### Breaking Change

```bash
git commit -m "$(cat <<'EOF'
feat(api)!: change authentication response format

BREAKING CHANGE: Auth endpoint now returns { token, user }
instead of just the token string. Update all clients.

Closes N43-156
EOF
)"
```

### Bug Fix

```bash
git commit -m "$(cat <<'EOF'
fix(api): handle null values in sentiment analysis

Previously crashed when review text was null.
Now returns empty sentiment object.

Fixes N43-167
EOF
)"
```

### Cursor/Agent Workflow

```bash
# Cursor command or rule (tooling)
git commit -m "chore(cursor): add commit command for conventional commits"

# Cursor reference documentation
git commit -m "docs(cursor): add git workflow reference from Notion"

# Agent planning files
git commit -m "chore(cursor): add feature plan for user authentication"
```

### Smart Branching Example

**Scenario**: On branch `ryan/n43-149-add-user-auth`, but staged changes are all in `.cursor/commands/`:

```
$ git branch --show-current
ryan/n43-149-add-user-auth

$ git diff --cached --stat
 .cursor/commands/git/commit.md | 150 ++++++++++++++++++++++++++++++++++
 1 file changed, 150 insertions(+)
```

**Agent Analysis**:

```
⚠️ Staged changes may not relate to current issue

Current Issue: N43-149 - Add user authentication
Changed Files: .cursor/commands/git/commit.md

These changes appear to be Dev Tooling work, not Authentication work.

Options:
A) Create new Linear issue and branch (recommended)
B) Commit to current branch anyway
C) Cancel
```

**If user selects A**:

```
Creating Linear issue...
  Title: Enhance commit command with Linear integration
  Team: Studio
  Labels: Domain → Dev Tooling, Issue Type → Feature
  Status: In Progress

Created: N43-201

Generating branch name...
  Username (from Linear): ryan
  Slug: add-linear-commit (shortened from "Enhance commit command with Linear integration")

Branch point preference:
A) From main (independent work) - recommended
B) From current branch (dependent work)

[User selects A]

Creating branch: ryan/n43-201-add-linear-commit
Switching to new branch...

Ready to commit. Proceeding with standard flow...
```

---

## Validation Checklist

Before committing, verify:

- [ ] Not on `main` branch
- [ ] Feature branch has an associated Linear issue
- [ ] Staged changes are relevant to the branch's Linear issue
- [ ] Type is appropriate for the change
- [ ] Scope matches affected area (or omitted for broad changes)
- [ ] Description is in imperative mood ("add" not "added")
- [ ] Description is concise (<50 chars ideally)
- [ ] Body explains "what" and "why" (not "how")
- [ ] Linear issue linked if applicable
- [ ] Breaking changes documented with `!` and footer

## Notes

- Squash related commits before PR review
- Each commit should be independently deployable
- When in doubt, make smaller, more frequent commits
- Use `git commit --amend` to fix the last commit (before pushing)
