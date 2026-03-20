> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Git log analysis, cross-issue aggregation, project status composition -->

# Update Projects

Scan recent **git** activity, optionally **correct Linear issue statuses** against reality, and post **project-level** status updates. Use before standups, end of week, or when stakeholders need a rollup.

## Same intent as chat (no slash required)

Natural asks should run **this exact procedure**—not a one-off paraphrase:

- *“Look at all commits since my last project updates and update every relevant Linear project for this repo.”*
- *“Sync Linear projects from git since we last posted updates.”*
- *“Cross-reference recent commits with Linear and post project status updates.”*

**Mechanism:** `git log` → extract issue ids → **Linear MCP** `get_issue` (state, project, title) → optional `save_issue` (§5) → draft + confirm → `save_status_update` per project (§6). The command file is the spec; chat text is just another trigger.

## How this maps to a Cursor command

1. **File:** `commands/linear/update-projects.md` in **n43-cursor**, symlinked or copied into this repo as **`.cursor/commands/linear/update-projects.md`**.
2. **Invocation:** Type **`/linear/update-projects`** (or pick it from the command palette). Cursor injects the file as context; `$ARGUMENTS` is anything after the command on the same line.
3. **Parity with chat:** You can also paste the natural-language bullets above in a normal message; the agent should still follow this document if **`linear-traceability`** / **`linear-sync`** / your rules say “use `/linear/update-projects` for project rollups.”

**Input:** `$ARGUMENTS` — optional time window (default **7 days**). Examples:

- `/linear/update-projects`
- `/linear/update-projects since Monday`
- `/linear/update-projects last 3 days`
- `/linear/update-projects since-last-sync`
- `/linear/update-projects --dry-run`
- `/linear/update-projects --status-only`
- `/linear/update-projects --projects-only`
- `/linear/update-projects --health offTrack`

---

## 1. Resolve time window

Pick **one** (first match):

| Trigger | `git --since` |
| ------- | ------------- |
| User gives a date/window (`since Monday`, `last 3 days`, ISO date) | Translate to `git`-compatible `--since=` |
| `$ARGUMENTS` contains **`since-last-sync`** **or** user says *since last project update* / *since we last synced projects* | Read repo root **`AGENTS.md`** for a line matching `(?i)^\s*lastLinearProjectUpdateSyncAt:\s*(\S+)\s*$` (ISO-8601 instant or date). Use that value as `--since`. **If missing:** tell the user to set it once (e.g. after their last manual Linear post) or fall back to **7 days** and say you fell back. |
| Default | `--since="7 days ago"` |

**After successful §6 posts** (user approved drafts, not `--dry-run`): with user consent, add or update **`lastLinearProjectUpdateSyncAt: <ISO-8601 now>`** in **`AGENTS.md`** so the next *since last sync* run only includes **new** commits.

Linear MCP does **not** replace `git log` for “what changed in the repo”—use it to **resolve issues and projects** and to **post** updates. Optionally cross-check: if MCP exposes listing recent project updates for a project, you may use the latest matching update time as a secondary hint; if unavailable, rely on **`lastLinearProjectUpdateSyncAt`**.

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

From branch names and **full** commit messages (including footers: `Refs`, `Closes`, `Fixes`, `Resolves`), collect matches with `/\b([A-Za-z][A-Za-z0-9]+-\d+)\b/g` on the raw text, then **normalize each match to uppercase**. **Deduplicate**. Personal branches without an issue in the name are fine when commit footers carry the ids (e.g. `Refs n43-351` and `Refs N43-351` both count).

If **none** found, report and stop (no project posts — nothing to group by project).

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

## Troubleshooting: “Nothing posted to projects”

| Cause | What to check |
| ----- | ------------- |
| Stopped at §3 | Recent commits in the window actually include a Linear key (`TEAM-123`) in **subject or body** (footer). Shallow clone / wrong repo / empty window → no IDs. |
| No project on issues | In Linear, issues must be **assigned to a Project** for §6 to target it. |
| Approval never given | §6 step 3: drafts + health must be **confirmed** before `save_status_update`. |
| Flags | `--dry-run` or `--status-only` prevents posting. |
| MCP errors | Agent summary should list failed `save_status_update` calls. |

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
