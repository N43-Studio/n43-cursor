> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Git log analysis, cross-issue aggregation, project status composition -->

# Update Projects

Scan recent **git** activity, optionally **correct Linear issue statuses** against reality, and post **project-level** status updates. Use before standups, end of week, or when stakeholders need a rollup.

**Input:** `$ARGUMENTS` — optional time window (default **7 days**). Examples:

- `/linear/update-projects`
- `/linear/update-projects since Monday`
- `/linear/update-projects last 3 days`
- `/linear/update-projects --dry-run`
- `/linear/update-projects --status-only`
- `/linear/update-projects --projects-only`
- `/linear/update-projects --health offTrack`

---

## 1. Resolve time window

Default: `--since="7 days ago"`. If the user specifies text (e.g. `since Monday`), translate to a `git` `--since=` value or equivalent.

---

## 2. Gather git activity

Run (adjust `--since` to the resolved window):

```bash
git log --all --oneline --since="<window>" --format="%h|%s|%an|%ar"
git branch -a
git log --all --since="<window>" --name-only --format="%h%n%B%n---COMMIT---"
```

Capture repo name from `git rev-parse --show-toplevel` or folder name for the report header.

---

## 3. Extract Linear issue IDs

From branch names and **full** commit messages (including footers: `Refs`, `Closes`, `Fixes`, `Resolves`), collect matches with `/\b([A-Z][A-Z0-9]+-\d+)\b/g` (case-insensitive on input, **normalize uppercase**). **Deduplicate**. Personal branches without an issue in the name are fine when commit footers carry the ids.

If **none** found, report and stop.

---

## 4. Fetch Linear issues

For each ID, Linear MCP `get_issue`:

- id, title, state, url, **project** (id + name if present)

---

## 5. Optional: verify issue statuses (`--status-only` or full run unless `--projects-only`)

Use **heuristics** only; ask the user when unsure.

| Signal | Suggested state | Action |
| ------ | --------------- | ------ |
| Commits in window on a branch naming issue **X**, no PR mentioned | In Progress | If Linear is Backlog/Todo/Unstarted → `save_issue` **In Progress** (forward-only) |
| User says PR is open for **X** | In Review | Transition forward if not already Done/Cancelled |
| User says PR merged | Done | Prefer leaving to **GitHub ↔ Linear** integration if enabled; else suggest manual or `save_issue` **Done** only if team policy allows |

List **mismatches** you fixed vs **uncertain** items for the user.

**Skip** this section entirely if `--projects-only`.

---

## 6. Project status updates (`--projects-only` or full run unless `--status-only`)

1. **Group** issues that have a **project** by `project.id` (or name).
2. For each project with at least one issue that had **commits in the window** (or that you adjusted in §5), draft a **Markdown** body:

```markdown
## Status update — <repo> (<start> – <end>)

### N43-123: <title> (<state>)
- `abc1234` <subject> (<n> files)
- ...

### N43-456: <title> (<state>)
- ...

---
_Generated from git activity_
```

3. **Before** calling Linear MCP `save_status_update`, **show drafts** to the user and confirm:
   - **health** per project: `onTrack` (default), `atRisk`, or `offTrack` (or `--health` override for all)
   - Any copy edits

4. For each approved project:

```
CallMcpTool: project-0-workspace-Linear / save_status_update
Arguments: {
  "type": "project",
  "project": "<project name or id>",
  "health": "onTrack",
  "body": "<markdown>"
}
```

**If `--dry-run`:** show drafts and **do not** call `save_status_update` (or `save_issue` from §5).

**Skip** §6 if `--status-only`.

---

## 7. Report

Summarize:

- Issues considered (IDs + titles)
- Status corrections (if any)
- Project updates posted (project names + health)
- **Warnings:** issues with **no** project (suggest assigning in Linear); branches without issue IDs; ambiguous cases

---

## Safety

- Never **create** issues from this command unless the user explicitly asks.
- Never transition **backward**.
- Never post project updates with **zero** supporting activity without user override.
- Prefer **user approval** for project status bodies and health.
