> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Deep code analysis, security review, nuanced pattern recognition -->

> **Agent**: `.cursor/agents/reviewer.md` — Use for delegated reviews via the orchestrator

# Review PR

Conduct a structured code review of a GitHub PR or branch, generating a review document with categorized feedback.

## Input

Accepts one of:

- GitHub PR URL (e.g., `https://github.com/org/repo/pull/123`)
- Remote branch name (e.g., `username/n43-123-feature-name`)
- No argument = review current branch

## Reference

Read `.cursor/skills/pr-review/SKILL.md` for review conventions.
Read `.cursor/skills/git-workflow/SKILL.md` for git workflow conventions.
Read `.cursor/rules/project-context.mdc` for project-specific code standards.

---

## Severity Levels

| Severity     | Description                                                                                                      | Blocking |
| ------------ | ---------------------------------------------------------------------------------------------------------------- | -------- |
| `nit`        | Strong but largely unimportant opinion. Stylistic preference that won't affect functionality or maintainability. | No       |
| `suggestion` | Loose opinion that can be discarded. A possible improvement the author may choose to ignore.                     | No       |
| `minor`      | Non-blocking if merged, but should be addressed in a follow-up commit.                                           | No       |
| `major`      | Must be addressed before this code can be merged to production.                                                  | Yes      |

---

## Feedback Types

In addition to severity-based feedback, use these types to categorize findings:

| Type       | Description                                                                                            | Guidelines                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `question` | Needs clarification from the commit author. Feedback may or may not be needed depending on the answer. | Use when intent is unclear or a design decision needs explanation.                  |
| `praise`   | A pattern, technique, or clever bit of code that deserves appreciation.                                | Include only **2-3** per review. Don't overuse—highlight genuinely impressive work. |

**Nit vs Suggestion:**

- `nit`: "I feel strongly about this, but it doesn't really matter" (e.g., naming preference, formatting)
- `suggestion`: "Here's an idea you could consider" (e.g., alternative approach, optional optimization)

---

## Process

### 1. Input Resolution

Determine the branch to review based on input:

```bash
# If GitHub PR URL provided
if [[ "$INPUT" == *"github.com"*"/pull/"* ]]; then
  # Extract PR info using gh CLI
  PR_INFO=$(gh pr view "$INPUT" --json headRefName,baseRefName)
  REVIEW_BRANCH=$(echo $PR_INFO | jq -r '.headRefName')
  PARENT_BRANCH=$(echo $PR_INFO | jq -r '.baseRefName')

# If branch name provided
elif [[ -n "$INPUT" ]]; then
  REVIEW_BRANCH="$INPUT"
  # Parent will be determined from upstream or default to main

# If no input, use current branch
else
  REVIEW_BRANCH=$(git branch --show-current)
fi
```

### 2. Branch Setup

Prepare for analysis without modifying the original branch:

```bash
# Save current branch to return later
ORIGINAL_BRANCH=$(git branch --show-current)

# Fetch latest from remote
git fetch origin

# Checkout the target branch
git checkout "$REVIEW_BRANCH"

# Determine parent branch
PARENT_BRANCH=${PARENT_BRANCH:-$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|origin/||' || echo "main")}

# Create review branch
git checkout -b "${REVIEW_BRANCH}/review"
```

### 3. Change Analysis

View all changes as a single diff:

```bash
# Find merge base
MERGE_BASE=$(git merge-base HEAD "origin/${PARENT_BRANCH}")

# Soft reset to see all changes
git reset --soft "$MERGE_BASE"

# Generate diff with context
git diff --cached --stat
git diff --cached

# List changed files with status
git diff --cached --name-status

# Get diff with line numbers for each file
git diff --cached --unified=5
```

---

## Conducting the Review

### 1. Read Project Context

Before reviewing, read these files to understand project standards:

- `.cursor/rules/project-context.mdc` - TypeScript, React, backend conventions
- `.cursor/skills/git-workflow/SKILL.md` - Commit and code standards
- `.cursor/skills/testing-logging/SKILL.md` - Testing patterns (if tests modified)

### 2. Review Each Changed File

For each file in the diff, evaluate:

**Code Quality:**

- Does it follow project naming conventions?
- Is the code readable and well-structured?
- Are there any obvious bugs or edge cases missed?

**TypeScript:**

- Are types explicit and correct?
- Are interfaces used for object shapes?
- Is strict mode honored?

**React (if frontend):**

- Are components small and focused?
- Are hooks used correctly?
- Is Tailwind CSS used for styling?

**Backend (if API changes):**

- Is async/await used properly?
- Is error handling consistent?
- Is logging structured?

### 3. Classify Each Finding

For each issue found:

1. Determine severity (`nit`/`suggestion`/`minor`/`major`) or type (`question`/`praise`)
2. Note the file path
3. Note the line number(s)
4. Write clear, actionable feedback
5. Use "we" or "the code" instead of "you"

**Choosing between nit and suggestion:**

- Use `nit` when you have a strong opinion but it doesn't matter much (formatting, naming preferences)
- Use `suggestion` when offering an alternative the author can freely ignore (optional optimizations, different approaches)

**Using question and praise:**

- Use `question` when clarification is needed before giving feedback
- Use `praise` sparingly (2-3 per review) for genuinely impressive patterns or solutions

### 4. Compile General Feedback

Note any cross-cutting concerns:

- Missing tests for new functionality
- Missing documentation updates
- Architectural concerns
- Performance implications
- Security considerations

**Praise budget:** Identify 2-3 genuinely noteworthy patterns or solutions to highlight in the Praise section.

---

## Report Template

Generate the review document using this format:

````markdown
# PR Review: {branch-name}

**Reviewed**: {date}
**Branch**: `{review-branch}`
**Base**: `{parent-branch}`
**Commits**: {commit-count}
**Files Changed**: {file-count}

## Summary

{1-2 sentence summary of what this PR does}

## Verdict

**Status**: APPROVED / CHANGES REQUESTED / NEEDS DISCUSSION

| Severity   | Count |
| ---------- | ----- |
| Major      | X     |
| Minor      | Y     |
| Suggestion | Z     |
| Nit        | W     |
| Question   | Q     |

---

## Major Issues

Issues that must be addressed before merging.

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Description of the issue and why it's major}

**Suggestion:**

```{language}
{suggested code or approach}
```
````

---

## Minor Issues

Issues that should be addressed, but are non-blocking.

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Description and suggestion}

---

## Suggestions

Loose opinions that can be discarded. Alternative approaches the author may choose to ignore.

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Description of the alternative approach and potential benefits}

---

## Nits

Strong but largely unimportant opinions. Stylistic preferences.

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Brief suggestion}

---

## Questions

Items needing clarification from the commit author. Feedback may depend on the answer.

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Question about intent, design decision, or unclear code}

---

## Praise

Patterns, techniques, or clever bits of code that deserve appreciation (2-3 max).

### 1. {Brief title}

**File**: `{filepath}`
**Line(s)**: {line-numbers}

{Why this is noteworthy—good pattern, elegant solution, etc.}

---

## General Feedback

Cross-cutting concerns and observations.

### Missing Elements

- [ ] {Missing documentation, tests, etc.}

### Other Observations

- {Architectural concerns, performance implications, security considerations}

---

## Files Reviewed

| File         | Status                 | Lines Changed |
| ------------ | ---------------------- | ------------- |
| `{filepath}` | Modified/Added/Deleted | +X/-Y         |

---

````

---

## Save and Cleanup

After generating the review:

```bash
# Create pr-reviews directory if needed
mkdir -p .cursor/plans/pr-reviews

# Save the review document
# Filename: {branch-name}-review.md (replace / with -)
REVIEW_FILE=".cursor/plans/pr-reviews/${REVIEW_BRANCH//\//-}-review.md"

# After review is complete, return to original branch
git checkout "$ORIGINAL_BRANCH"

# Optionally delete review branch
# git branch -D "${REVIEW_BRANCH}/review"
````

---

## Examples

### Example 1: Review by PR URL

```bash
# Input
/review-pr https://github.com/n43/riley/pull/42

# Output
# → Checks out PR #42's branch
# → Creates {branch}/review
# → Generates .cursor/plans/pr-reviews/{branch}-review.md
```

### Example 2: Review by Branch Name

```bash
# Input
/review-pr colin/n43-173-get-store-real-reviews

# Output
# → Fetches and checks out the branch
# → Creates colin/n43-173-get-store-real-reviews/review
# → Compares against main (or upstream)
# → Generates review document
```

### Example 3: Review Current Branch

```bash
# Input (no arguments, on feature branch)
/review-pr

# Output
# → Reviews current branch against its parent
```

### Example 4: Sample Review Findings

**Major:**

````markdown
### 1. Missing error handling in API call

**File**: `backend/src/routes/reviews.ts`
**Line(s)**: 45-52

The `fetchReviews` call doesn't handle the case where the API returns a 429 (rate limit). This could crash the server in production.

**Suggestion:**

```typescript
try {
  const reviews = await fetchReviews(placeId)
  // ...
} catch (error) {
  if (error.status === 429) {
    return res.status(429).json({ error: "Rate limited, try again later" })
  }
  throw error
}
```
````

````

**Minor:**
```markdown
### 1. Consider extracting magic number
**File**: `frontend/src/components/ReviewCard.tsx`
**Line(s)**: 23

The value `150` for truncation length could be a named constant for clarity.

**Suggestion:** `const MAX_PREVIEW_LENGTH = 150;`
````

**Suggestion:**

```markdown
### 1. Consider using a Map for lookup

**File**: `backend/src/utils/transform.ts`
**Line(s)**: 34-42

The array `.find()` here works fine, but if this list grows, a Map would give O(1) lookups. Just a thought—the current approach is perfectly acceptable for the expected data size.
```

**Nit:**

```markdown
### 1. Prefer `const` for non-reassigned variables

**File**: `backend/src/utils/transform.ts`
**Line(s)**: 78

`let reviewCount` is never reassigned—could be `const` for clarity. Strong preference, but doesn't affect functionality.
```

**Question:**

```markdown
### 1. Intentional inclusion of deleted reviews?

**File**: `backend/src/routes/reviews.ts`
**Line(s)**: 67

The query includes soft-deleted reviews (`deletedAt IS NOT NULL`). Is this intentional for an audit trail, or should these be filtered out for the user-facing response?
```

**Praise:**

```markdown
### 1. Elegant retry logic with exponential backoff

**File**: `backend/src/utils/rapidApi.ts`
**Line(s)**: 89-112

The retry wrapper with configurable backoff and jitter is well-designed. Clean separation of concerns and handles edge cases like max retries gracefully. This pattern could be extracted as a utility for other API calls.
```

---

## Notes

### Branch Safety

- The original PR branch is never modified
- The `/review` branch is a local-only duplicate for analysis
- Delete the review branch after completing the review if desired

### Handling Edge Cases

| Scenario                   | Behavior                                           |
| -------------------------- | -------------------------------------------------- |
| Branch doesn't exist       | Error message with suggestion to check branch name |
| No commits ahead of parent | Note in review that branch has no changes          |
| Uncommitted local changes  | Stash changes, warn user, continue                 |
| PR already merged          | Can still review by checking out the branch        |
| `gh` CLI not authenticated | Fall back to branch name input only                |

### Best Practices

1. **Be specific** - Always include file and line references
2. **Be constructive** - Explain why something is an issue
3. **Prioritize** - Major items first, nits last
4. **Acknowledge good work** - Use the Praise section (2-3 items max)
5. **Ask questions** - If intent is unclear, use the Questions section instead of assuming
6. **Distinguish opinion strength** - Use `nit` for strong preferences, `suggestion` for loose ideas

### Review Checklist Reference

Before finalizing review, verify coverage of:

- [ ] Code correctness and logic
- [ ] Error handling
- [ ] Type safety
- [ ] Security implications
- [ ] Performance considerations
- [ ] Test coverage
- [ ] Documentation needs
- [ ] Conventional commit compliance
