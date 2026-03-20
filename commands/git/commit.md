> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

> **Why**: Change analysis, commit message crafting, Linear integration

# Commit

Create a properly formatted git commit with intelligent Linear issue management.

## Reference

Read `.cursor/references/git-workflow.md` for full commit conventions.

## Quick Path (Normal Commit)

The [Branch Guard](#0-branch-guard) always runs first (**never** commit on `main`).

- If the **branch name includes a Linear issue id** (same patterns as [Step 1b](#1b-resolve-primary-linear-issue)) and you're confident the staged work belongs on this branch, you may jump to [Standard Commit Flow](#4-standard-commit-flow) (still run [4f-linear-footer-inject](#4f-linear-footer-inject) if the composed message lacks `Refs` / `Closes` / `Fixes` / `Resolves` for that id).
- If the branch is a **personal branch** (no issue in the name), you **must not** skip [Step 1b](#1b-resolve-primary-linear-issue) — resolve **P**, then [4f-linear-footer-inject](#4f-linear-footer-inject), then **4f**.

After a successful commit, run [Step 5](#5-linear-issue-sync-this-commit) unless the user chose **Option B** (no Linear) when `get_issue` failed in Step 1b.

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

Direct commits to main are not allowed. Use a non-main working branch (personal dev
branch is fine). Linear linking uses commit footers (`Refs`, `Closes`, etc.) and/or
issue ids in the branch name.

Options:
A) Create/switch to your personal dev branch for this work
B) Switch to another existing non-main branch
C) Cancel
```

- If user selects **A**, create/switch to a personal branch (for example `ryan`) and restart from Step 0.
- If user selects **B**, ask which branch and run `git checkout <branch>`, then restart from Step 0.
- If user selects **C**, exit gracefully.

**If branch name does not contain a Linear issue ID** (no match for `[nN]43-\d+` in the branch string): **personal branch path** — still allowed. You **must** resolve a **primary Linear issue** in [Step 1b](#1b-resolve-primary-linear-issue) (via footer, `AGENTS.md`, conversation, or Linear MCP) and **must** include `Refs <ID>` (or `Closes` / `Fixes` / `Resolves`) for that ID in the commit footer before running `git commit` ([4f-linear-footer-inject](#4f-linear-footer-inject)).

Optional hardening (user preference):

```
⚠️ Personal branch (no issue in branch name)

Branch: <current-branch-name>

You can keep this branch. The agent will attach Linear via the commit footer (`Refs N43-XXX`).

Options:
A) Continue — resolve issue in Step 1b and auto-inject footer (default)
B) Create a new Linear issue and switch to <user>/<issue>-<slug> (recommended for long-lived work)
C) Cancel
```

- If **B**, proceed to [Create Linear Issue](#3-create-linear-issue-option-a).
- If **C**, exit gracefully.
- Otherwise continue to [Analyze Changes](#1-analyze-changes).

**If on a branch whose name contains a Linear issue ID**: Continue to [Analyze Changes](#1-analyze-changes) (issue also comes from branch in Step 1b).

---

### 1. Analyze Changes

Run these commands to understand what's being committed:

```bash
# View staged changes
git diff --cached --stat

# View detailed changes
git diff --cached
```

### 1b. Resolve primary Linear issue

Determine **one** primary issue ID (uppercase, e.g. `N43-149`) for this commit. Use the **first** source that succeeds:

| Order | Source | How |
| ----- | ------ | --- |
| 1 | **Branch name** | Regex `(?i)\b(n43-\d+)\b` or, for other team keys, `(?i)\b([a-z]{2,10}-\d+)\b` inside the branch string (e.g. `colin/n43-351-e2e` → `N43-351`). Prefer the **first** match that looks like a Linear key (`[A-Z][A-Z0-9]+-\d+` after normalization). |
| 2 | **Commit message draft** (if already drafted) | Footer lines `Refs`, `Closes`, `Fixes`, `Resolves` with `N43-123` style IDs — use the **main** work item (first `Closes`/`Fixes`/`Resolves`, else first `Refs`). |
| 3 | **User message / thread** | User said “N43-351”, “this is for 351”, linked issue, etc. |
| 4 | **`AGENTS.md` (repo root)** | Line matching `(?i)^\s*defaultLinearIssue:\s*([A-Z][A-Z0-9]+-\d+)\s*$` or under a `## Linear` section the same pattern. |
| 5 | **Linear MCP** | `list_issues` with `assignee: "me"`, `state: "In Progress"` (or active states your team uses), `limit: 10`. If **exactly one** issue matches, use it. If **multiple**, list them and ask the user to pick **once** (or they set `defaultLinearIssue` in `AGENTS.md`). |

Then fetch issue details:

- Linear MCP `get_issue` with the resolved ID
- Capture: title, description, labels

```
CallMcpTool: project-0-workspace-Linear / get_issue
Arguments: { "id": "N43-149" }
```

**If no primary ID can be resolved:** STOP and tell the user to add `defaultLinearIssue: N43-XXX` to **`AGENTS.md`**, rename the branch to include the issue id, or specify the issue in chat — then retry.

**Error Handling**: If Linear MCP call fails:

1. Do NOT silently fall back to standard commit
2. Ask the user:
   - **Option A**: Reconnect/reauth to Linear first (user can fix MCP connection)
   - **Option B**: Proceed without Linear integration (standard commit flow)
3. If user selects A, provide guidance:
   - Check MCP server status
   - Verify Linear authentication
   - Restart MCP connection if needed
4. If user selects B, skip to [Standard Commit Flow](#4-standard-commit-flow) and **skip [Step 5](#5-linear-issue-sync-this-commit)** (no Linear MCP calls after commit)

### 1c. Assess Work Relevance

Evaluate whether staged changes relate to the **primary** Linear issue from Step 1b:

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

### Step 5: Choose Working Branch

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

**Default Branch Model**: personal dev branch `<firstname>` (for example `ryan`).

**Optional Isolated Branch Model** (only when needed): `<firstname>/<issue-id>-<short-slug>`

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

**Default Example**: `ryan`

**Optional Isolated Example**: `ryan/n43-201-add-linear-commit`

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

### 4d. Linear footer lines

Issue linking is in the commit footer (issue ids in branch names are optional):

- Use **`Refs N43-XXX`** to link without closing (default for ongoing work on personal branches).
- Use **`Closes` / `Fixes` / `Resolves`** when the commit should close the issue on merge.
- Multiple issues: one per line.

### 4e. Format Commit Message

```
<type>(<scope>): <short description in imperative mood>

[Optional longer description explaining what and why]

[Closes N43-XXX]
[BREAKING CHANGE: description if applicable]
```

### 4f-linear-footer-inject

Before **4f**, take the composed message body (subject + body + footer). Let **P** be the **primary issue ID** (normalized uppercase): use the ID from Step 1b if you ran it; if you used the [Quick Path](#quick-path-normal-commit) from a branch that already contains an issue id, derive **P** from the branch with the same regex as Step 1b row 1; if **P** is still unknown, **stop** and run Step 1b first.

If **P** is set and the message does **not** already reference **P** in a footer line (`Refs`, `Closes`, `Fixes`, `Resolves`, `Blocks`, `Blocked by`, `Related to`), **append**:

```text

Refs P
```

(use the actual id, e.g. `Refs N43-351`)

Do **not** duplicate `Refs P` if `Closes P` / `Fixes P` / `Resolves P` is already present.

### 4f. Create Commit

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<body if needed>

<footer>
EOF
)"
```

## 5. Linear issue sync (this commit)

After **4f. Create Commit** succeeds, keep the **primary** Linear issue aligned with local work. **No activity comments** on the issue—only **status** and **relationships**. A **full batch** sync for everything you push still runs via [`/git/push`](./push.md) (preferred).

### 5a. Preconditions

- **Skip entirely** if the user chose **Option B** (proceed without Linear) in [Step 1b](#1b-resolve-primary-linear-issue).
- Otherwise use the **primary** issue ID from Step 1b (same as **P** in [4f-linear-footer-inject](#4f-linear-footer-inject)). Normalize to uppercase (e.g. `n43-149` → `N43-149`).

### 5b. Status (forward-only)

1. Linear MCP `get_issue` with the **primary** issue ID.
2. If the issue state is **Backlog**, **Unstarted**, or **Todo** (case-insensitive match on name), call `save_issue` with `id` set to that issue and `state: "In Progress"`.
3. If already **In Progress**, **In Review**, **Done**, or **Cancelled**, do **not** change state (never regress).

```
CallMcpTool: project-0-workspace-Linear / get_issue
Arguments: { "id": "N43-149" }

CallMcpTool: project-0-workspace-Linear / save_issue
Arguments: { "id": "N43-149", "state": "In Progress" }
```

### 5c. Relationships from this commit message

Read the **full** message of the commit you just created (`git log -1 --format=%B`). Extract other Linear identifiers with `/\b([A-Z][A-Z0-9]+-\d+)\b/g`. Let **primaryIssue** be the ID from Step 1b; ignore **primaryIssue** when it is only the self-target of a close line (same as before for “branch issue”).

From the footer/body, map keywords to `save_issue` fields (all IDs uppercase). **Append-only** in Linear—safe to re-run.

| Pattern in message | `save_issue` field | Notes |
| ------------------ | ------------------ | ----- |
| `Refs <ID>` / `Ref <ID>` / `Related to <ID>` | `relatedTo: ["<ID>"]` | Multiple lines → merge unique IDs |
| `Blocks <ID>` | `blocks: ["<ID>"]` | |
| `Blocked by <ID>` | `blockedBy: ["<ID>"]` | |
| `Closes <ID>` / `Fixes <ID>` / `Resolves <ID>` where `<ID>` ≠ primaryIssue | `relatedTo: ["<ID>"]` | GitHub still closes on merge; this links the issues in Linear |

Call **one** `save_issue` on **primaryIssue** with only the non-empty arrays (omit empty fields). Example:

```
CallMcpTool: project-0-workspace-Linear / save_issue
Arguments: {
  "id": "N43-149",
  "relatedTo": ["N43-200"],
  "blocks": ["N43-201"]
}
```

If there are **no** relationship lines, skip 5c.

### 5d. Error handling

If any Linear MCP call in Step 5 fails:

1. Tell the user: **Commit succeeded; Linear sync failed:** `<error>`
2. Do **not** roll back the commit.
3. Suggest fixing MCP/auth or running `/git/push` later for a batch sync.

---

## Edge Cases & Error Handling

### No Linear issue resolvable

Personal dev branches do not need issue IDs in the branch name; use footers (`Refs`, `Closes`, etc.). If the branch has **no** issue id **and** Step 1b cannot resolve a primary issue (`AGENTS.md`, thread, or Linear MCP), stop and ask the user to set **`defaultLinearIssue: N43-XXX`** in **`AGENTS.md`** or name the issue in chat. Once **P** is known, [4f-linear-footer-inject](#4f-linear-footer-inject) adds `Refs` when missing.

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

4. **If user selects B**, continue with standard commit flow and **skip [Step 5](#5-linear-issue-sync-this-commit)**

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

**Scenario**: On branch `ryan`, but staged changes suggest a distinct logical unit:

```
$ git branch --show-current
ryan

$ git diff --cached --stat
 .cursor/commands/git/commit.md | 150 ++++++++++++++++++++++++++++++++++
 1 file changed, 150 insertions(+)
```

**Agent Analysis**:

```
⚠️ Staged changes may not relate to current issue

Changed Files: .cursor/commands/git/commit.md

These changes appear to be Dev Tooling work and should be linked to a specific Linear issue in commit footer.

Options:
A) Create new Linear issue (recommended)
B) Commit to current branch anyway (with explicit issue footer)
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

Continuing on personal branch: ryan

Ready to commit. Proceeding with standard flow...
```

---

## Validation Checklist

Before committing, verify:

- [ ] Not on `main` branch
- [ ] On a non-main working branch (personal branch preferred)
- [ ] Commit footer links relevant Linear issue(s) when applicable
- [ ] Type is appropriate for the change
- [ ] Scope matches affected area (or omitted for broad changes)
- [ ] Description is in imperative mood ("add" not "added")
- [ ] Description is concise (<50 chars ideally)
- [ ] Body explains "what" and "why" (not "how")
- [ ] Linear issue linked if applicable
- [ ] Breaking changes documented with `!` and footer
- [ ] After commit: [Step 5](#5-linear-issue-sync-this-commit) run (status + relationships), unless Linear was skipped (Option B in Step 1b)
- [ ] Remind user: **`/git/push`** runs a **batch** Linear sync for the full pushed range (preferred over relying on commit-only sync)

## Notes

- Squash related commits before PR review
- Each commit should be independently deployable
- When in doubt, make smaller, more frequent commits
- Use `git commit --amend` to fix the last commit (before pushing)
