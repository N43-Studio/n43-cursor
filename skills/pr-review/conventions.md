# PR Review Conventions

Detailed conventions for conducting effective code reviews.

---

## Table of Contents

1. [Severity Levels](#severity-levels)
2. [Feedback Types](#feedback-types)
3. [Conducting the Review](#conducting-the-review)
4. [Classify Each Finding](#classify-each-finding)
5. [Compile General Feedback](#compile-general-feedback)
6. [Report Template](#report-template)
7. [Example Findings](#example-findings)
8. [Best Practices](#best-practices)
9. [Review Checklist Reference](#review-checklist-reference)

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

---

## Classify Each Finding

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

---

## Compile General Feedback

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

`````

---

## Example Findings

### Example Major Issue

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
`````

### Example Minor Issue

```markdown
### 1. Consider extracting magic number

**File**: `frontend/src/components/ReviewCard.tsx`
**Line(s)**: 23

The value `150` for truncation length could be a named constant for clarity.

**Suggestion:** `const MAX_PREVIEW_LENGTH = 150;`
```

### Example Suggestion

```markdown
### 1. Consider using a Map for lookup

**File**: `backend/src/utils/transform.ts`
**Line(s)**: 34-42

The array `.find()` here works fine, but if this list grows, a Map would give O(1) lookups. Just a thought—the current approach is perfectly acceptable for the expected data size.
```

### Example Nit

```markdown
### 1. Prefer `const` for non-reassigned variables

**File**: `backend/src/utils/transform.ts`
**Line(s)**: 78

`let reviewCount` is never reassigned—could be `const` for clarity. Strong preference, but doesn't affect functionality.
```

### Example Question

```markdown
### 1. Intentional inclusion of deleted reviews?

**File**: `backend/src/routes/reviews.ts`
**Line(s)**: 67

The query includes soft-deleted reviews (`deletedAt IS NOT NULL`). Is this intentional for an audit trail, or should these be filtered out for the user-facing response?
```

### Example Praise

```markdown
### 1. Elegant retry logic with exponential backoff

**File**: `backend/src/utils/rapidApi.ts`
**Line(s)**: 89-112

The retry wrapper with configurable backoff and jitter is well-designed. Clean separation of concerns and handles edge cases like max retries gracefully. This pattern could be extracted as a utility for other API calls.
```

---

## Best Practices

1. **Be specific** - Always include file and line references
2. **Be constructive** - Explain why something is an issue
3. **Prioritize** - Major items first, nits last
4. **Acknowledge good work** - Use the Praise section (2-3 items max)
5. **Ask questions** - If intent is unclear, use the Questions section instead of assuming
6. **Distinguish opinion strength** - Use `nit` for strong preferences, `suggestion` for loose ideas

---

## Review Checklist Reference

Before finalizing review, verify coverage of:

- [ ] Code correctness and logic
- [ ] Error handling
- [ ] Type safety
- [ ] Security implications
- [ ] Performance considerations
- [ ] Test coverage
- [ ] Documentation needs
- [ ] Conventional commit compliance

---

## Verdict Decision Guide

| Condition                                     | Verdict                     |
| --------------------------------------------- | --------------------------- |
| Any major issues present                      | CHANGES REQUESTED           |
| Unanswered questions that may reveal blockers | NEEDS DISCUSSION            |
| Only minor/suggestion/nit items               | APPROVED (with suggestions) |
| All concerns addressed or only praise         | APPROVED                    |
