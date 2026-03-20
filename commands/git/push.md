> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

> **Why**: Remote sync, commit-range analysis, batch Linear issue updates

# Push

Push the current branch to `origin` and **batch-sync Linear** for every issue touched by commits in the push range. This is the **preferred** Linear path (aligns with what actually landed on the remote).

**No activity comments** on issues—only **status** (forward-only) and **relationships** parsed from commit footers.

## Reference

- Commit flow and footer conventions: [commit.md](./commit.md)
- Git conventions: `.cursor/skills/git-workflow/SKILL.md` (or `.cursor/references/git-workflow.md`)

## Input

`$ARGUMENTS` may include extra `git push` flags (e.g. `--force-with-lease`). Apply them to the `git push` invocation after the safety checks below.

---

## 1. Preconditions

1. `git branch --show-current` — **do not** push from `main` unless the user explicitly confirms they intend to (default: stop and use a feature branch).
2. Confirm working tree state if needed (`git status`).

---

## 2. Capture push range **before** `git push`

After a successful push, `HEAD` and `@{u}` often match—**record the range first**.

1. Current branch: `BRANCH=$(git branch --show-current)`
2. Resolve the **base** (first match that works):

   **A.** If upstream is configured:

   ```bash
   git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
   ```

   If this succeeds, the range is:

   ```bash
   git log @{u}..HEAD --format=%H
   git log @{u}..HEAD --format=%B
   ```

   **B.** Else if `origin/$BRANCH` exists locally:

   ```bash
   git rev-parse "origin/$BRANCH" 2>/dev/null
   ```

   Range: `origin/$BRANCH..HEAD`

   **C.** Else try `origin/main` or `origin/master`:

   ```bash
   git merge-base HEAD origin/main 2>/dev/null   # or origin/master
   ```

   Range: `<merge-base>..HEAD` **or** `origin/main..HEAD` if merge-base is unavailable.

3. If the range **cannot** be determined reliably, **warn** the user, then either:
   - abort until they set upstream (`git push -u origin "$BRANCH"`), or
   - proceed with `git push` only and **skip** Linear batch (document why).

4. Store the list of commit hashes and **full** commit messages (`%B`) for all commits in the range. If the range is **empty**, still run `git push` if the user wants (nothing new locally); then **skip** Linear (no commits to attribute).

---

## 3. Run `git push`

```bash
git push -u origin "$BRANCH"   # add $ARGUMENTS if user provided flags
```

- On **failure**: report error and **do not** run Linear batch (remote did not advance as expected).
- On **success**: continue to Step 4.

---

## 4. Batch Linear sync (pushed commits)

### 4a. Collect issue IDs

1. Regex on **branch name** and **every pushed commit** subject + body: `/\b([A-Z][A-Z0-9]+-\d+)\b/g` (normalize each match to uppercase).
2. **Deduplicate** the set of IDs.

### 4b. Branch primary issue

Extract **primary** issue ID from the branch name (same pattern as `/git/commit`: `[nN]43-\d+` or, for other teams, `/[A-Za-z][A-Za-z0-9]+-\d+/` → normalize uppercase). Most relationship footers apply to **primary** (the branch you pushed).

### 4c. For each unique issue ID in the range

Collect IDs from **branch name + every pushed commit** (full message) with `/\b([A-Z][A-Z0-9]+-\d+)\b/g` (case-insensitive input, normalize to uppercase). Deduplicate.

For **each** ID `I` in that set:

1. `get_issue` with `I`.
2. **Status:** If state is **Backlog**, **Unstarted**, or **Todo**, call `save_issue` with `id: I` and `state: "In Progress"`. Never regress **In Review** / **Done** / **Cancelled**.

### 4d. Relationships (merged onto primary)

For **primary** only: scan **all pushed** commit messages. For each message, apply the same footer rules as [`/git/commit` Step 5c](./commit.md#5c-relationships-from-this-commit-message) (`Refs` / `Related to` / `Blocks` / `Blocked by` / cross-issue `Closes|Fixes|Resolves`), ignoring the primary ID when it is the only target of a self-close line.

Merge into **one** `save_issue` call for **primary** with combined unique `relatedTo`, `blocks`, `blockedBy` arrays (omit empty fields). If nothing to add, skip the relationship `save_issue`.

Example MCP calls:

```
CallMcpTool: project-0-workspace-Linear / get_issue
Arguments: { "id": "N43-149" }

CallMcpTool: project-0-workspace-Linear / save_issue
Arguments: { "id": "N43-149", "state": "In Progress", "relatedTo": ["N43-200"] }
```

### 4e. Error handling

- If a Linear call fails for one issue, log it and **continue** with the others.
- Summarize successes and failures for the user.

---

## 5. Report

Return:

1. Push result (branch, remote).
2. Commit range summary (# commits, hashes).
3. Linear: issues touched, status changes, relationship updates, errors.

---

## Notes

- **Idempotent:** Re-running after the same remote state may repeat append-only relations; status no-ops if already **In Progress**.
- Commit-time sync in `/git/commit` [Step 5](./commit.md#5-linear-issue-sync-this-commit) still runs for **local** safety; this command is the **batch** reconciliation on push.
