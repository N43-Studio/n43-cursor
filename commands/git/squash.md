> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Branch analysis, commit grouping, message composition -->

> **Agent**: `.cursor/agents/squasher.md` — Use for delegated squashing via the orchestrator

# Squash Branch

Create a clean, squashed version of the current git branch for PR readiness without modifying the original branch.

## Reference

- `.cursor/skills/git-workflow/SKILL.md` - Git workflow conventions (quick reference)
- `.cursor/skills/git-workflow/reference.md` - Full git workflow reference
- `.cursor/rules/git-workflow.mdc` - Project git conventions (always-applied rule)

## Process

### 1. Pre-Flight Checks

Verify the working directory is ready for squashing:

```bash
# Ensure working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: Working directory has uncommitted changes. Commit or stash them first."
    exit 1
fi

# Check if we're in a git repository
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || {
    echo "ERROR: Not in a git repository"
    exit 1
}
```

### 2. Branch Discovery

Identify the current branch and its parent:

```bash
# Get current branch name
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

# Ensure we're not on main/master
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    echo "ERROR: Cannot squash main/master branch"
    exit 1
fi

# Get upstream branch or default to main
PARENT_BRANCH=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|origin/||' || echo "main")
echo "Parent branch: $PARENT_BRANCH"

# Find merge base (where this branch diverged from parent)
MERGE_BASE=$(git merge-base $CURRENT_BRANCH $PARENT_BRANCH)
echo "Merge base: $MERGE_BASE"

# Count commits to squash
COMMIT_COUNT=$(git rev-list --count $MERGE_BASE..HEAD)
echo "Commits to squash: $COMMIT_COUNT"

# Exit if no commits to squash
if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo "No commits to squash. Branch is up-to-date with $PARENT_BRANCH."
    exit 0
fi
```

### 3. Commit Analysis

Analyze commits to understand grouping options:

```bash
# List all commits with stats
echo "=== Commits to squash ==="
git log --oneline --stat $MERGE_BASE..HEAD

# Show commits with their files changed
echo -e "\n=== Commits with files changed ==="
git log --oneline --name-only $MERGE_BASE..HEAD

# Group commits by conventional commit type
echo -e "\n=== Commits by type ==="
git log --oneline $MERGE_BASE..HEAD | grep -E "^[a-f0-9]+ (feat|fix|refactor|docs|chore|test|style|perf|build|ci)" || echo "(No conventional commits found)"

# Group by scope (if present)
echo -e "\n=== Commits by scope ==="
git log --oneline $MERGE_BASE..HEAD | sed -n 's/.*(\([^)]*\)).*/\1/p' | sort | uniq -c | sort -rn || echo "(No scopes found)"

# Find commits referencing Linear issues
echo -e "\n=== Commits with Linear issues ==="
git log --oneline --grep="N43-" $MERGE_BASE..HEAD || echo "(No Linear issues referenced)"

# Check for merge commits (warn if present)
MERGE_COMMITS=$(git log --merges --oneline $MERGE_BASE..HEAD | wc -l)
if [ "$MERGE_COMMITS" -gt 0 ]; then
    echo -e "\n⚠️  WARNING: Branch contains $MERGE_COMMITS merge commit(s)."
    echo "Consider using manual approach for complex merge histories."
fi
```

### 4. Commit Grouping Analysis

Analyze commits to determine the optimal squash strategy:

#### Decision Tree

```
┌─────────────────────────────────────────────────────────────┐
│                    DECISION TREE                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  All commits share same Linear issue?                       │
│  ├─ YES → Single squash (one commit)                        │
│  └─ NO ↓                                                    │
│                                                             │
│  All commits have file dependencies?                        │
│  ├─ YES → Single squash (one commit)                        │
│  └─ NO ↓                                                    │
│                                                             │
│  Can commits be cleanly separated into independent groups?  │
│  ├─ YES → How many groups?                                  │
│  │   ├─ 2-3 groups → Grouped squash (N commits)             │
│  │   └─ 4+ groups → Split into separate -squash-X branches  │
│  └─ NO → Single squash (safest option)                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Grouping Priority

| Priority | Factor                 | Grouping Rule                                |
| -------- | ---------------------- | -------------------------------------------- |
| 1        | **Linear Issue**       | Same `N43-XXX` in message → same group       |
| 2        | **File Dependency**    | Commits with file overlap → same group       |
| 3        | **Conventional Scope** | Same `(scope)` in commit type → same group   |
| 4        | **Directory Cluster**  | Same top-level directory → same group        |
| 5        | **Commit Type**        | Same type (feat/fix/etc) → consider grouping |

#### Dependency Analysis Commands

```bash
# Check for file overlaps between commits
# (Two commits are dependent if they modify the same file)

# List all files modified per commit
git log --format="%H" $MERGE_BASE..HEAD | while read sha; do
    echo "=== $sha ==="
    git show --name-only --format="" $sha
done

# Compare files between two specific commits
# git show --name-only --format="" <sha1> | sort > /tmp/files1.txt
# git show --name-only --format="" <sha2> | sort > /tmp/files2.txt
# comm -12 /tmp/files1.txt /tmp/files2.txt  # Shows overlapping files
```

### 5. Create Squash Branch

Create a duplicate branch for squashing:

```bash
# Define squash branch name
SQUASH_BRANCH="${CURRENT_BRANCH}-squash"

# Check if squash branch already exists
if git show-ref --verify --quiet refs/heads/$SQUASH_BRANCH; then
    echo "⚠️  Squash branch '$SQUASH_BRANCH' already exists."
    echo "Options:"
    echo "  1. Delete it: git branch -D $SQUASH_BRANCH"
    echo "  2. Use different name: git checkout -b ${CURRENT_BRANCH}-squash-v2"
    exit 1
fi

# Create squash branch from current branch
git checkout -b "$SQUASH_BRANCH"
echo "Created squash branch: $SQUASH_BRANCH"
```

### 6. Squash Execution

Choose the appropriate squash method based on analysis:

#### Method A: Single Squash (All commits into one)

Use when all commits are related or have dependencies:

```bash
# Soft reset to merge base (keeps all changes staged)
git reset --soft $MERGE_BASE

# Create new commit with comprehensive message
# Use conventional commit format from the primary type/scope
git commit -m "$(cat <<'EOF'
feat(scope): comprehensive description of all changes

- Detail 1 of what was changed
- Detail 2 of what was changed
- Detail 3 of what was changed

Closes N43-XXX
EOF
)"
```

#### Method B: Grouped Squash (Multiple logical commits)

Use when commits can be grouped by scope/type but have dependencies:

```bash
# This requires manual steps:
# 1. Soft reset to merge base
git reset --soft $MERGE_BASE

# 2. Unstage all files
git reset HEAD

# 3. Stage and commit files by group
# Group 1: API changes
git add backend/src/**
git commit -m "feat(api): description of API changes"

# Group 2: UI changes
git add frontend/src/**
git commit -m "feat(ui): description of UI changes"

# Group 3: Documentation
git add docs/** README.md
git commit -m "docs: update documentation"
```

#### Method C: Split Branches (Independent work streams)

Use when commits are truly independent (no file overlaps):

```bash
# First, validate independence by testing cherry-picks
git checkout -b test-independence $PARENT_BRANCH

# Test Group 1
git cherry-pick <commit-shas-for-group-1>
# If conflicts, groups are NOT independent - use Method A or B

# If successful, create actual split branches
git checkout $CURRENT_BRANCH
git checkout -b "${CURRENT_BRANCH}-squash-api"
# Reset and cherry-pick only API commits

git checkout $CURRENT_BRANCH
git checkout -b "${CURRENT_BRANCH}-squash-ui"
# Reset and cherry-pick only UI commits

# Clean up test branch
git branch -D test-independence
```

### 7. Verification

**Critical**: Verify the squashed branch has identical final state:

```bash
# Return to original branch temporarily
ORIGINAL_HEAD=$(git rev-parse HEAD)

# Compare trees (should show NO differences)
echo "=== Verifying squash integrity ==="
DIFF_OUTPUT=$(git diff ${CURRENT_BRANCH} ${SQUASH_BRANCH})

if [ -z "$DIFF_OUTPUT" ]; then
    echo "✅ PASS: Squash branch matches original branch exactly"
else
    echo "❌ FAIL: Squash branch differs from original!"
    echo "Differences:"
    git diff --stat ${CURRENT_BRANCH} ${SQUASH_BRANCH}
    echo ""
    echo "⚠️  DO NOT push this squash branch. Investigate the differences."
fi

# Verify commit count reduced
SQUASH_COMMIT_COUNT=$(git rev-list --count $MERGE_BASE..HEAD)
echo ""
echo "Original commits: $COMMIT_COUNT"
echo "Squashed commits: $SQUASH_COMMIT_COUNT"
```

### 8. Push to Origin (Optional)

Push the squash branch to remote:

```bash
# Push squash branch
git push -u origin "${SQUASH_BRANCH}"

# If split branches were created
# git push -u origin "${CURRENT_BRANCH}-squash-api"
# git push -u origin "${CURRENT_BRANCH}-squash-ui"
```

### 9. Return to Original Branch

After squashing, return to your original branch:

```bash
# Return to original branch
git checkout $CURRENT_BRANCH

echo ""
echo "=== Squash Complete ==="
echo "Original branch: $CURRENT_BRANCH (unchanged)"
echo "Squash branch:   $SQUASH_BRANCH (ready for PR)"
echo ""
echo "Next steps:"
echo "  1. Review squash branch: git log --oneline $SQUASH_BRANCH"
echo "  2. Push squash branch:   git push -u origin $SQUASH_BRANCH"
echo "  3. Open PR from:         $SQUASH_BRANCH → $PARENT_BRANCH"
```

---

## Examples

### Example 1: Simple Squash (3 commits → 1)

**Before (on `colin/n43-100-add-feature`):**

```
abc123 feat(api): add user endpoint
def456 fix(api): handle null in user endpoint
ghi789 WIP: testing user endpoint
```

**After (on `colin/n43-100-add-feature-squash`):**

```
xyz789 feat(api): add user endpoint with null handling

Implements GET /api/users with proper null value handling.

Closes N43-100
```

**Commands:**

```bash
# Create squash branch
git checkout -b colin/n43-100-add-feature-squash

# Squash all commits
git reset --soft $(git merge-base HEAD main)
git commit -m "$(cat <<'EOF'
feat(api): add user endpoint with null handling

Implements GET /api/users with proper null value handling.

Closes N43-100
EOF
)"

# Verify
git diff colin/n43-100-add-feature colin/n43-100-add-feature-squash
# Should be empty
```

### Example 2: Grouped Squash (10 commits → 3 by scope)

**Before:**

```
aaa111 feat(api): add auth middleware
bbb222 feat(api): add protected routes
ccc333 fix(api): fix middleware error
ddd444 feat(ui): add login form
eee555 feat(ui): add logout button
fff666 style(ui): format login form
ggg777 docs: add auth README
hhh888 chore: update dependencies
iii999 test(api): add auth tests
jjj000 fix(ui): fix login validation
```

**After:**

```
xxx111 feat(api): add authentication with middleware and protected routes

Includes auth middleware, protected routes, and comprehensive tests.

xxx222 feat(ui): add login/logout functionality

Implements login form with validation and logout button.

xxx333 chore: update dependencies and documentation
```

### Example 3: Split Branches (Independent features)

**Before (on `colin/n43-200-multiple-features`):**

```
aaa111 feat(api): add health endpoint
bbb222 docs: update README
ccc333 feat(ui): add dark mode toggle
ddd444 chore(build): update eslint config
```

**After (4 separate branches):**

- `colin/n43-200-multiple-features-squash-api` → `feat(api): add health endpoint`
- `colin/n43-200-multiple-features-squash-docs` → `docs: update README`
- `colin/n43-200-multiple-features-squash-ui` → `feat(ui): add dark mode toggle`
- `colin/n43-200-multiple-features-squash-build` → `chore(build): update eslint config`

---

## Safety Checks

### Before Starting

- [ ] Working directory is clean (`git status --porcelain` is empty)
- [ ] Not on main/master branch
- [ ] Branch has commits ahead of parent
- [ ] No uncommitted changes

### During Squash

- [ ] Squash branch created from current branch
- [ ] Only working on squash branch, not original
- [ ] Using `--soft` reset to preserve changes

### After Squash

- [ ] Original branch is unchanged
- [ ] Parent branch is unchanged
- [ ] `git diff original squash` shows no differences
- [ ] Squash branch has correct commit message(s)

### Abort Procedure

If something goes wrong:

```bash
# If on squash branch and need to abort
git checkout $CURRENT_BRANCH
git branch -D $SQUASH_BRANCH

# If squash branch was pushed and needs removal
git push origin --delete $SQUASH_BRANCH

# Your original branch is always safe
```

---

## Edge Cases

### Branch with no commits ahead of parent

```bash
# The script will exit with message
echo "No commits to squash. Branch is up-to-date with $PARENT_BRANCH."
```

### Branch with merge commits

```bash
# Warning will be shown
echo "⚠️  Branch contains merge commits. Consider manual approach."
```

### Branch name with special characters

Branch names following Linear's format (`username/n43-xxx-description`) are fully supported.

### Squash branch already exists

```bash
# Options provided
echo "Delete it: git branch -D $SQUASH_BRANCH"
echo "Use different name: git checkout -b ${CURRENT_BRANCH}-squash-v2"
```

### Working directory has uncommitted changes

```bash
# Error shown, must handle changes first
echo "ERROR: Working directory has uncommitted changes."
echo "Options: git stash, git commit, or git checkout -- ."
```

---

## Notes

- **Original branch is NEVER modified** - all work happens on the `-squash` branch
- **Parent branch is NEVER modified** - only used to find merge base
- **Verification is critical** - always run `git diff` to confirm identical final state
- **Use `git branch -D`** to delete squash branches if you need to start over
- **Force push may be needed** if re-squashing: `git push --force-with-lease origin $SQUASH_BRANCH`
- **Interactive rebase is avoided** because it requires interactive input not available in Cursor

---

## Branch Naming Convention

Following Linear's pattern with `-squash` suffix:

| Branch Type  | Naming Pattern                              |
| ------------ | ------------------------------------------- |
| Original     | `username/n43-xxx-feature-name`             |
| Squash       | `username/n43-xxx-feature-name-squash`      |
| Split (API)  | `username/n43-xxx-feature-name-squash-api`  |
| Split (UI)   | `username/n43-xxx-feature-name-squash-ui`   |
| Split (Docs) | `username/n43-xxx-feature-name-squash-docs` |

---

## Quick Reference

```bash
# Full squash workflow
CURRENT_BRANCH=$(git branch --show-current)
PARENT_BRANCH=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|origin/||' || echo "main")
MERGE_BASE=$(git merge-base $CURRENT_BRANCH $PARENT_BRANCH)

git checkout -b "${CURRENT_BRANCH}-squash"
git reset --soft $MERGE_BASE
git commit -m "feat(scope): comprehensive description"

# Verify
git diff $CURRENT_BRANCH "${CURRENT_BRANCH}-squash"

# Return to original
git checkout $CURRENT_BRANCH
```
