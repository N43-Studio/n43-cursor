> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Git log analysis, cross-issue aggregation, project status composition -->

# Update Projects

Scan recent **git** activity, optionally **correct Linear issue statuses** against reality, and post **project-level** status updates. Use before standups, end of week, or when stakeholders need a rollup.

## Same intent as chat (no slash required)

Natural asks should run **this exact procedure**—not a one-off paraphrase:

- *“Look at all the commits since my last project updates and update every relevant Linear project for this repo.”*
- *“Sync Linear projects from git since we last posted updates.”*
- *“Cross-reference recent commits with Linear and post project status updates.”*

**Mechanism:** `git log` → load **Studio OS** initiative projects + issues from Linear → **match every commit** (explicit issue refs + smart text/path overlap) → `get_issue` where needed → optional `save_issue` (§5) → draft + confirm → `save_status_update` per project (§6). The command file is the spec; chat text is just another trigger.

## How this maps to a Cursor command

1. **File:** `commands/linear/update-projects.md` in **n43-cursor**, symlinked or copied into this repo as **`.cursor/commands/linear/update-projects.md`**.
2. **Invocation:** Type **`/linear/update-projects`** (or pick it from the command palette). Cursor injects the file as context; `$ARGUMENTS` is anything after the command on the same line.
3. **Parity with chat:** You can also paste the natural-language bullets above in a normal message; the agent should still follow this document if **`linear-traceability`** / **`linear-sync`** / your rules say “use `/linear/update-projects` for project rollups.”

**Input:** `$ARGUMENTS` — optional time window (default **7 days**). Optional initiative override: e.g. `/linear/update-projects initiative="Other Initiative"` if not Studio OS. Examples:

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

Linear MCP does **not** replace `git log` for “what changed in the repo”—use it to **resolve initiatives, projects, issues** and to **post** updates. Optionally cross-check: if MCP exposes listing recent project updates for a project, you may use the latest matching update time as a secondary hint; if unavailable, rely on **`lastLinearProjectUpdateSyncAt`**.

---

## 2. Gather git activity

Run (adjust `--since` to the resolved window):

```bash
git log --all --oneline --since="<window>" --format="%h|%s|%an|%ar"
git branch -a
git log --all --since="<window>" --name-only --format="%h%n%B%n---COMMIT---"
```

Capture repo name from `git rev-parse --show-toplevel` or folder name for the report header.

Parse into a list of **commits**, each with at least: `hash`, `subject`, `body`, **`files[]`** (paths from the name-only section).

---

## 3. Map commits to Linear (explicit + Studio OS initiative)

**Do not** stop when no regex ids are found. Always load the initiative corpus (§3b) and run attribution (§3c).

### 3a. Explicit issue IDs (high confidence)

From branch names and **full** commit messages (including footers: `Refs`, `Closes`, `Fixes`, `Resolves`), collect matches with `/\b([A-Za-z][A-Za-z0-9]+-\d+)\b/g`, **normalize to uppercase**, dedupe.

For each id, you will `get_issue` in §4 and attach commits that contain that id to that issue’s **project**.

### 3b. Load Studio OS initiative corpus (Linear MCP)

Resolve initiative name (first match):

| Source | Value |
| ------ | ----- |
| `$ARGUMENTS` / user text | e.g. `initiative="Studio OS"` |
| Repo root **`AGENTS.md`** | Line `(?i)^\s*linearStudioOsInitiative:\s*(.+)\s*$` |
| Default | **`Studio OS`** |

Use Linear MCP (your workspace’s Linear server, e.g. `plugin-linear-linear`):

1. **`get_initiative`** with `query` = that name, **`includeProjects`: true** (and `includeSubInitiatives` if your workspace nests initiatives).
2. If `get_initiative` is ambiguous or empty, fall back to **`list_projects`** with `initiative` set to the same name (and `team` from `AGENTS.md` `linearTeam:` if needed, else infer from context).
3. For **each project** in that initiative, call **`list_issues`** with `project` = project name or id, **`limit` up to 250**, paginate with `cursor` until no more issues or cap at **500 issues per project** (document if truncated).

Build an in-memory **corpus**:

- `Project` → `{ id, name, slug?, issues: [{ id, title }] }`

Optional: merge **`AGENTS.md`** hints, e.g.

```text
linearProjectPathHints: Gastown -> gastown, topology, runner
linearProjectPathHints: Prospect Researcher Agent -> outreach, prospeo, prospect
```

(parse however is consistent for your repo). Use hints as **extra tokens** when scoring that project.

### 3c. Heuristic attribution (compare commits to corpus)

For each commit **not** already fully explained by explicit ids in §3a:

1. Build **`commitText`**: `subject + "\n" + body + "\n" + files.join(" ")`, lowercased.
2. Extract **structural tokens**:
   - Conventional commit scope: `feat(foo):` / `fix(bar)!:` → token `foo`, `bar`
   - Path segments: split paths on `/`, keep segments that look like feature areas (e.g. `gastown`, `ventures`, `universe`, `outreach`, `notion`, `dashboard`); drop generic dirs (`src`, `app`, `components`, `lib`, `test`, `tests`, `__tests__`) unless they are the only signal.
3. For **each project** in the corpus, compute a **score** (sum, cap per line item as noted):
   - **+5** if any **issue id** for that project appears in the commit message.
   - **+4** if the **project name** (or significant word >3 chars from it) appears in `commitText`.
   - **+3** per **issue title** word (>3 chars, not stopwords) that appears in `subject` or `body` (cap +9 per project).
   - **+3** per overlap between **path tokens / scope** and project **name words** or **`linearProjectPathHints`** tokens (cap +12).
4. Let **best** = max score, **second** = second-highest. **Assign** the commit to that project when:
   - `best >= 6`, and
   - `best - second >= 3` **or** `best >= 10`.
5. Otherwise mark the commit **Unscoped** (still list it in the §8 report).

**Tie-breaking:** If two projects tie within 2 points, prefer the one that contains an explicit issue id match from §3a; else leave **Unscoped** or label **Low confidence** and mention both in the draft.

**Labels for the Markdown draft:**

- **`[explicit]`** — commit references issue id in message/branch.
- **`[inferred]`** — placed via §3c scoring; always say scores are heuristic.

---

## 4. Fetch Linear issue details

For **each unique explicit issue id** from §3a, Linear MCP **`get_issue`**: id, title, state, url, project.

For **inferred** commits, you may **`get_issue`** only when you need fresh state for §5 (e.g. issue titles already in corpus); do not spam `get_issue` for every issue in a project unless necessary.

---

## 5. Optional: verify issue statuses (`--status-only` or full run unless `--projects-only`)

Use **heuristics** only; ask the user when unsure. Prefer acting on **explicit-id** commits over pure `[inferred]` mapping.

| Signal | Suggested state | Action |
| ------ | --------------- | ------ |
| Commits in window on a branch naming issue **X**, no PR mentioned | In Progress | If Linear is Backlog/Todo/Unstarted → `save_issue` **In Progress** (forward-only) |
| User says PR is open for **X** | In Review | Transition forward if not already Done/Cancelled |
| User says PR merged | Done | Prefer leaving to **GitHub ↔ Linear** integration if enabled; else suggest manual or `save_issue` **Done** only if team policy allows |

List **mismatches** you fixed vs **uncertain** items for the user.

**Skip** this section entirely if `--projects-only`.

---

## 6. Project status updates (`--projects-only` or full run unless `--status-only`)

1. **Group** by **Linear project** (from initiative): include all commits mapped in §3 (explicit or inferred).
2. For each project with **at least one** commit in the window, draft **Markdown**:

```markdown
## Status update — <repo> (<start> – <end>)

### Confirmed (issue references)
#### N43-123: <title> (<state>)
- `[hash]` [explicit] <subject> …

### Inferred from commit text / paths (heuristic — review)
- `[hash]` [inferred] <subject> — _matched: <short reason>_

### Unscoped commits (no confident project)
- `[hash]` <subject> — _suggest linking via Refs or AGENTS hints_

---
_Generated from git activity + Studio OS initiative cross-reference_
```

3. **Before** calling Linear MCP **`save_status_update`**, **show drafts** to the user and confirm:
   - **health** per project: `onTrack` (default), `atRisk`, or `offTrack` (or `--health` override for all)
   - Whether to **omit** or **soften** `[inferred]` sections if they look wrong

4. For each approved project, call MCP **`save_status_update`** (use your workspace Linear server id):

```
CallMcpTool: <linear-mcp-server> / save_status_update
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
| Initiative empty / wrong name | `get_initiative` / `list_projects` for **Studio OS** (or override). Set `linearStudioOsInitiative:` in **`AGENTS.md`**. |
| All commits Unscoped | Add **`linearProjectPathHints`** or improve issue titles in Linear; use **`Refs`** on commits for certainty. |
| No project on issues (explicit path) | Issues must be on a **Project** that sits under the initiative for rollup. |
| Approval never given | §6 step 3: drafts + health must be **confirmed** before `save_status_update`. |
| Flags | `--dry-run` or `--status-only` prevents posting. |
| MCP errors | Agent summary should list failed calls. |

---

## 7. Report

Summarize:

- Initiative + **project** list loaded
- Issues referenced explicitly (IDs + titles)
- Per-project: **explicit** vs **inferred** commit counts; **Unscoped** list
- Status corrections (if any)
- Project updates posted (project names + health)
- **Warnings:** truncated issue lists, weak matches, missing `AGENTS.md` hints

---

## Safety

- Never **create** issues from this command unless the user explicitly asks.
- Never transition **backward**.
- Never post project updates with **zero** supporting activity without user override (explicit + inferred commits count as activity).
- **Do not** claim an issue is done based only on `[inferred]` mapping.
- Prefer **user approval** for project status bodies, health, and questionable `[inferred]` blocks.
