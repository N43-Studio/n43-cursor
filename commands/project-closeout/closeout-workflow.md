> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Cross-system reasoning across git, Linear, and filesystem state -->

# Project Closeout Workflow

Take a long-lived Ralph branch from iterative development to a coherent, reviewable, merge-ready end state.

## When to Use

Run this workflow when a Ralph project branch has reached feature-complete and needs to transition from "working state" to "shippable state." Typical triggers:

- All PRD issues are `Done`
- The branch has diverged significantly from `main` (10+ commits, many changed files)
- Transient runtime artifacts have accumulated (`.ralph/`, `progress.txt`, `run-log.jsonl`)

## Reference

- `commands/git/squash.md` — Squash branch preparation
- `commands/git/release-notes.md` — Release notes generation
- `templates/project-closeout/closeout-checklist.md` — Actionable checklist template

## Stages

### Stage 1: Inventory

Understand the scope of divergence before making any changes.

```bash
BRANCH=$(git branch --show-current)
PARENT=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|origin/||' || echo "main")
MERGE_BASE=$(git merge-base "$BRANCH" "$PARENT")

echo "=== Branch Divergence Report ==="
echo "Branch:     $BRANCH"
echo "Parent:     $PARENT"
echo "Merge base: $MERGE_BASE"
echo ""

COMMIT_COUNT=$(git rev-list --count "$MERGE_BASE..HEAD")
echo "Commits: $COMMIT_COUNT"

echo ""
echo "=== Files Changed ==="
git diff --stat "$MERGE_BASE..HEAD"

echo ""
echo "=== Changed files by directory ==="
git diff --name-only "$MERGE_BASE..HEAD" | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn

echo ""
echo "=== Untracked files ==="
git ls-files --others --exclude-standard
```

**Output**: A divergence report capturing commit count, changed files, directory breakdown, and untracked files.

### Stage 2: Artifact Triage

Classify every file outside the canonical codebase into one of three categories.

#### Classification Rules

| Category | Definition | Action | Examples |
|---|---|---|---|
| **Transient** | Runtime byproducts with no long-term value | Delete from branch | `.ralph/results/`, `progress.txt`, `run-log.jsonl`, `assumptions-log.jsonl` |
| **Archival** | Artifacts with historical value but no place in the merged codebase | Attach to Linear project, then delete | Retrospective JSON, run-log entries, calibration snapshots |
| **Canonical** | Files that belong in the merged codebase | Retain | Contracts, scripts, commands, skills, templates, README updates |

#### Transient Artifacts (delete)

These are generated during Ralph runtime and must not be merged:

```
.ralph/results/                  # Per-issue iteration results
.ralph/results-*/                # Retry result directories
.ralph/squash-artifacts/         # Squash plan/mapping JSONs
progress.txt                     # Loop progress tracker
run-log.jsonl                    # Runtime execution log
assumptions-log.jsonl            # Assumption tracking (if present)
```

#### Archival Artifacts (attach to Linear, then delete)

These carry project history worth preserving outside the repo:

```
.cursor/ralph/*/retrospective.json    # Project retrospective
run-log.jsonl                         # Attach before deleting
.cursor/ralph/*/review-queue.json     # Review decisions
```

To archive, attach the file content as a Linear project update or comment before deletion.

#### Canonical Artifacts (retain)

Everything that was the *purpose* of the branch:

```
contracts/                  # Ralph contracts and protocols
commands/                   # Cursor commands
scripts/                    # Shell/Node scripts
templates/                  # Reusable templates
skills/                     # Agent skills
rules/                      # Cursor rules
.cursor/agents/             # Native agents
README.md                   # Top-level docs
commands/README.md          # Command index
```

#### Cleanup Commands

```bash
# Remove transient artifacts
rm -rf .ralph/results/ .ralph/results-*/
rm -rf .ralph/squash-artifacts/
rm -f progress.txt run-log.jsonl assumptions-log.jsonl

# Remove empty .ralph/ if nothing remains
[ -d .ralph ] && [ -z "$(ls -A .ralph)" ] && rmdir .ralph

# Verify only canonical files remain
git status --short
```

### Stage 3: Coherence Review

Verify the remaining canonical files form a self-consistent set.

#### 3a. Cross-Reference Integrity

Check that contracts, commands, and READMEs reference each other correctly:

```bash
# Find references to files that don't exist
rg -l '\.\w+/' contracts/ commands/ templates/ | while read file; do
    rg -oP '`([^`]+\.(md|json|sh|js|mdc))`' "$file" | while read ref; do
        clean=$(echo "$ref" | tr -d '`')
        [ ! -f "$clean" ] && echo "BROKEN: $file references $clean"
    done
done
```

#### 3b. Orphan File Check

Identify files that exist but are not referenced by any command, contract, or README:

```bash
# List all markdown files not in .ralph/ or .cursor/plans/
git diff --name-only "$MERGE_BASE..HEAD" -- '*.md' | \
    grep -v '^\.ralph/' | \
    grep -v '^\.cursor/plans/' | \
    while read f; do
        REFS=$(rg -l "$(basename "$f")" --glob '*.md' --glob '*.mdc' | grep -v "$f" | wc -l)
        [ "$REFS" -eq 0 ] && echo "ORPHAN: $f (not referenced anywhere)"
    done
```

#### 3c. README Completeness

Verify index files list all entries in their directories:

- `commands/README.md` lists every `commands/**/*.md`
- `contracts/ralph/core/commands/README.md` lists every command contract

#### 3d. Contract-Command Parity

For each command in `commands/`, verify a corresponding contract exists in `contracts/` (where applicable), and vice versa.

### Stage 4: Release Summary

Generate human-readable release notes from the branch's commit history.

```bash
# Using the canonical release-notes script
node scripts/generate-release-notes.js \
    --since "$MERGE_BASE" \
    --until HEAD \
    --output .ralph/release-notes.md \
    --sidecar .ralph/release-notes.json
```

If the script is unavailable, generate release notes manually:

```bash
echo "# Release Notes: $BRANCH" > release-notes.md
echo "" >> release-notes.md
echo "## Summary" >> release-notes.md
echo "" >> release-notes.md
echo "Branch: \`$BRANCH\`" >> release-notes.md
echo "Commits: $COMMIT_COUNT" >> release-notes.md
echo "Files changed: $(git diff --name-only $MERGE_BASE..HEAD | wc -l | tr -d ' ')" >> release-notes.md
echo "" >> release-notes.md
echo "## Changes by Type" >> release-notes.md
echo "" >> release-notes.md

for type in feat fix refactor docs chore test; do
    ENTRIES=$(git log --oneline "$MERGE_BASE..HEAD" | grep "^[a-f0-9]* $type" || true)
    if [ -n "$ENTRIES" ]; then
        echo "### ${type}" >> release-notes.md
        echo "$ENTRIES" | while read line; do
            echo "- ${line#* }" >> release-notes.md
        done
        echo "" >> release-notes.md
    fi
done
```

### Stage 5: Squash/Merge Preparation

Prepare the branch for merge using the squash workflow.

Follow `commands/git/squash.md` for the full procedure. Key steps:

1. **Pre-flight**: Ensure working directory is clean (artifact cleanup from Stage 2 must be committed first)
2. **Commit the cleanup**: Stage and commit transient artifact removals as a `chore` commit
3. **Analyze commits**: Run commit grouping analysis
4. **Emit plan artifact**: Generate squash plan JSON
5. **Create squash branch**: `${BRANCH}-squash`
6. **Execute squash**: Single or grouped strategy based on analysis
7. **Verify equivalence**: `git diff $BRANCH ${BRANCH}-squash` must be empty
8. **Emit post-squash artifacts**: Commit mapping, verification, PR summary

```bash
# Commit cleanup first
git add -A
git commit -m "chore: remove transient Ralph runtime artifacts

Cleans up .ralph/results/, progress.txt, run-log.jsonl, and
other runtime artifacts before squash/merge preparation."

# Then follow commands/git/squash.md
```

### Stage 6: Linear Project Transition

Update Linear to reflect the project's completed state.

#### 6a. Verify Issue Status

All PRD issues should be in a terminal state (`Done` or `Cancelled`). Flag any that are not:

```
For each issue in prd.json:
  - Status should be "Done" or "Cancelled"
  - If "In Progress" or "Todo", investigate before closing
```

#### 6b. Attach Closeout Artifacts

Upload to the Linear project as updates or comments:

- Release notes (from Stage 4)
- Retrospective JSON (from archival artifacts)
- Run-log summary (attach before deletion)
- Squash verification (from Stage 5)

#### 6c. Update Project Status

- Set Linear project status to `Completed` (or equivalent)
- Add a final project update summarizing the closeout

#### 6d. Link PR

Once the squash branch is pushed and a PR is opened, link it to the Linear project and relevant issues.

## End State

After closeout, the branch should satisfy:

| Property | Verification |
|---|---|
| No transient artifacts | `git ls-files .ralph/results progress.txt run-log.jsonl` returns empty |
| All files are canonical | Every file serves a documented purpose |
| Cross-references are valid | No broken links between contracts, commands, READMEs |
| Release notes exist | Human-readable summary of all changes |
| Squash branch is ready | Tree-equivalent to source branch, clean commit history |
| Linear project is current | All issues terminal, closeout artifacts attached |
| Another developer can review | The PR is self-explanatory without oral history |

## Automation Opportunities

Future iterations may automate portions of this workflow:

- Stage 1 can be fully scripted (`scripts/branch-divergence-report.sh`)
- Stage 2 cleanup can use a `.ralph/artifact-manifest.json` to declaratively classify files
- Stage 3 cross-reference checks can be a pre-commit hook or CI step
- Stage 4 already has a script surface (`scripts/generate-release-notes.js`)
- Stage 5 already has a command surface (`commands/git/squash.md`)
- Stage 6 can integrate with Linear MCP for automated status transitions
