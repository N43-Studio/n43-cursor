> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Parsing and reformatting structured markdown, no deep reasoning required -->

# Organize PR Review for GitHub

Reorganize a PR review document from `.cursor/plans/pr-reviews/` into a format optimized for copy-pasting into GitHub's PR review UI. Feedback is grouped by filepath (alphabetically), with each item formatted concisely with line references and severity/type prefixes.

## Input

Accepts:

- Path to a review document (e.g., `.cursor/plans/pr-reviews/{branch}-review.md`)
- No argument = list available reviews in `.cursor/plans/pr-reviews/` and prompt for selection

## Reference

Read `.cursor/commands/code-review/review-pr.md` for the review document format.
Read `.cursor/skills/pr-review/SKILL.md` for severity levels and feedback types.

---

## Process

### 1. Load Review Document

If no path provided:

- List all `.md` files in `.cursor/plans/pr-reviews/` (excluding `README.md` and files prefixed with `DONE-`)
- Display file list
- Ask user which review to organize

If path provided:

- Verify file exists
- Load the review document

### 2. Parse All Feedback Items

Extract every feedback item from the review document across all sections:

- **Major Issues** (`## Major Issues`)
- **Minor Issues** (`## Minor Issues`)
- **Suggestions** (`## Suggestions`)
- **Nits** (`## Nits`)
- **Questions** (`## Questions`)
- **Praise** (`## Praise`)
- **General Feedback** (`## General Feedback`)

For each item, extract:

- **Severity/type**: `major`, `minor`, `suggestion`, `nit`, `question`, or `praise`
- **File path(s)**: From `**File**:` field or `###` heading (may reference multiple files)
- **Line number(s)**: From `**Line(s)**:`, `_Line_`, `_Lines_`, or `_Diff lines_` fields
- **Description**: The inline quote (e.g., `> major: ...`) or the body text
- **Suggestion/code block**: Any code suggestion attached to the item
- **Additional context**: Any `**Additional context:**` notes

Items without a file path (or from `## General Feedback`) are classified as general feedback.

### 3. Reorganize by Filepath

Group all extracted items by their file path, then sort:

1. **Alphabetically by filepath** (ascending, A→Z)
2. **Within each file, by line number** (ascending, lowest first)
3. **Within the same line range, by severity** (major → minor → suggestion → nit → question → praise)

### 4. Format Output

Output the reorganized review to the conversation using this format:

#### File-Specific Feedback

For each file (alphabetically):

````markdown
## path/to/file.ts

### L{start}-L{end}

```markdown
major: Concise description of the issue

**Suggestion:** //optional: use when appropriate
\`\`\`language
suggested code fix
\`\`\`
```

```markdown
nit: Another comment on this line range
```

### L{line}

```
praise: Nice pattern here
```
````

**Formatting rules:**

- File paths are `##` headings (no backticks, no bold)
- Line references are `###` headings using `L{n}` or `L{start}-L{end}` format
- Each feedback item is a single backtick-wrapped line: `` `severity: description` ``
- Keep descriptions concise (aim for <20 words) unless the feedback requires explanation
- If a feedback item has a code suggestion, include it as a fenced code block below the backtick line with a `**Suggestion:**` label
- If a feedback item has additional context, include it as a plain text line below prefixed with `**Additional context:**`
- If a single `###` heading (file) in the original review references multiple files, split into separate entries under each file path
- Separate each `##` file section with a blank line
- Separate each `###` line section with a blank line

#### General PR Feedback

After all file-specific feedback, include a general section:

````markdown
## General PR Feedback

```
Summary observations, cross-cutting concerns, and general notes.
- Missing tests for new functionality
- Consider breaking large PRs into smaller ones
```
````

**General feedback formatting rules:**

- Use a `##` heading: `General PR Feedback`
- Wrap the content in a fenced code block (triple backticks)
- Include items from the `## General Feedback` section of the original review
- Also include any feedback items that lack a specific file/line reference

### 5. Confirm Completion

After outputting the formatted review, ask the user:

> "Review formatted for GitHub. Are you done with this review? If so, I'll mark the original file with the `DONE-` prefix."

### 6. Mark as Done

If the user confirms:

1. Rename the original review file by prepending `DONE-` to the filename
   - e.g., `.cursor/plans/pr-reviews/branch-review.md` → `.cursor/plans/pr-reviews/DONE-branch-review.md`
2. Confirm the rename

If the user declines:

- Leave the file as-is
- Suggest they can re-run this command later

---

## Example

### Input (from review document)

The review document contains items organized by severity (Major Issues, Minor Issues, etc.) with file and line references scattered throughout.

### Output (formatted for GitHub)

````markdown
## .cursor/rules/project-context.mdc

### L36-L43

```
major: Unresolved merge conflict markers committed. Breaks tooling and agent instructions.

**Suggestion:**
\`\`\`
Resolve the conflict by keeping the correct reference documentation table.
\`\`\`
```

## .github/workflows/deploy-agent.yml

### L28

```
major: Feature branch hardcoded in push trigger. Dead code after merge.

**Suggestion:**

\`\`\`yaml
push:
  branches:
    - main
  paths:
    - ".github/workflows/**"
    - "agents/reviewResponseAgent/**"
\`\`\`

**Additional context:** Create a Linear TODO to address orphaned agent deployments from repeated pushes.
```

## agents/reviewResponseAgent/agent.py

### L9

```
nit: Inconsistent env var naming: GOOGLE_CLOUD_PROJECT vs GOOGLE_PROJECT_ID
```

### L76

```
nit: Model version mismatch between Python and TypeScript agents
```

## agents/reviewResponseAgent/deploy.py

### L59-L62

```
major: Always creates new agent instances, accumulating orphaned resources

**Suggestion:**

\`\`\`python
existing = agent_engines.list(filter=f'display_name="{engine_config["display_name"]}"')
if existing:
    remote_app = agent_engines.update(agent_engine=existing[0].resource_name, ...)
else:
    remote_app = agent_engines.create(agent_engine=root_agent, **engine_config)
\`\`\`
```

## agents/reviewResponseAgent/test.py

### L75

```
minor: Hardcoded agent ID becomes stale after redeployment
```

## backend/src/agents/reviewResponseAgent.ts

### L141

```
nit: Model version mismatch between Python and TypeScript agents
```

### L221-L245

```
minor: Duplicated buildMessage logic across reviewResponseAgent.ts and agentClient.ts
```

## backend/src/routes/reviewResponse.ts

### L24

```
suggestion: Add auth and rate limiting before production
```

**Additional context:** Not production-facing yet — create a Linear TODO before launch.

### L58-L64

```
nit: console.warn used for informational logging instead of console.info
```

## backend/src/utils/agentClient.ts

### L43

```
nit: Inconsistent env var naming: GOOGLE_CLOUD_PROJECT vs GOOGLE_PROJECT_ID
```

### L70-L74

```
nit: console.warn used for informational logging instead of console.info
```

### L178-L203

```
minor: Duplicated buildMessage logic across reviewResponseAgent.ts and agentClient.ts
```

## README.md

### L11

```
minor: Example says weatherAgent instead of reviewResponseAgent
```

## General PR Feedback

```
CHANGES REQUESTED — 2 major, 3 minor, 1 suggestion, 3 nits

Missing elements:
- Authentication/authorization on the new endpoint
- Rate limiting for the AI-powered endpoint
- Integration/unit tests for backend TypeScript code
- Environment variable documentation for Vertex AI connection

Other observations:
- PR scope is substantial (CI/CD, Python agent, backend TS, docs) — consider smaller PRs for future agent additions
- @google/adk at ^0.2.0 is pre-1.0; consider pinning to exact version
- .gitignore additions for Python artifacts are well-scoped
```
````

---

## Edge Cases

| Scenario                            | Behavior                                                                                 |
| ----------------------------------- | ---------------------------------------------------------------------------------------- |
| Review file doesn't exist           | Error: "Review not found at {path}. Run `/review-pr` first."                             |
| No reviews available                | Message: "No active reviews found in `.cursor/plans/pr-reviews/`."                       |
| Item references multiple files      | Split into separate entries under each file path                                         |
| Item has no line number             | Use `### (no line reference)` under the file heading                                     |
| Item has no file path               | Include in General PR Feedback section                                                   |
| File already has `DONE-` prefix     | Skip when listing available reviews                                                      |
| User declines marking done          | Leave file as-is, no rename                                                              |
| Review has only general feedback    | Output only the General PR Feedback section                                              |
| Diff line references (not absolute) | Use the diff line numbers as-is with `L` prefix (e.g., `_Diff lines 36-43_` → `L36-L43`) |

---

## Notes

- This command is **read-only** with respect to the review content — it reformats but does not edit feedback
- Use `/code-review/interactive-review` first if you need to refine, reprioritize, or dismiss items before formatting
- The formatted output is designed for manual copy-paste into GitHub PR review comments, not for programmatic submission
- The `DONE-` prefix convention matches the project's existing pattern for completed items (e.g., `DONE-{feature-name}/` in `.cursor/plans/`)

---

## Related Commands

| Command               | Relationship                                        |
| --------------------- | --------------------------------------------------- |
| `/review-pr`          | Generates the review documents this command formats |
| `/interactive-review` | Refines review content before formatting            |
| `/commit`             | Use after marking review done to commit the rename  |
