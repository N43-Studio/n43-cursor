> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Deep codebase analysis, architectural decisions, research synthesis -->

# Plan Feature

Generate a detailed implementation plan for the requested feature.

## Feature: $ARGUMENTS

## Usage Modes

This command can be run in two ways:

| Mode                 | How                                         | When                                      |
| -------------------- | ------------------------------------------- | ----------------------------------------- |
| **Standalone**       | Run `/implementation/plan-feature` directly | Manual workflow, full control             |
| **Via Orchestrator** | Subagent reads this methodology             | Automated via `/implementation/implement` |

Both modes use the same planning methodology. The orchestrator mode adds state management via `agent-session.json`.

---

## Mission

Transform a feature request into a **comprehensive implementation plan** through systematic codebase analysis, external research, and strategic planning.

**Core Principle**: We do NOT write code in this phase. Our goal is to create a context-rich implementation plan that enables one-pass implementation success.

**Key Philosophy**: Context is King. The plan must contain ALL information needed for implementation - patterns, mandatory reading, documentation, validation commands - so the execution agent succeeds on the first attempt.

## Planning Process

### Phase 1: Feature Understanding

**Deep Feature Analysis:**

- Extract the core problem being solved
- Identify user value and business impact
- Determine feature type: New Capability/Enhancement/Refactor/Bug Fix
- Assess complexity: Low/Medium/High
- Map affected systems and components

**Create User Story Format:**

```
As a <type of user>
I want to <action/goal>
So that <benefit/value>
```

### Phase 2: Codebase Intelligence Gathering

**1. Project Structure Analysis**

- Detect primary language(s), frameworks, and runtime versions
- Map directory structure and architectural patterns
- Identify service/component boundaries and integration points
- Locate configuration files (package.json, tsconfig.json, etc.)
- Find environment setup and build processes

**2. Pattern Recognition**

- Search for similar implementations in codebase
- Identify coding conventions:
  - Naming patterns (camelCase, PascalCase, etc.)
  - File organization and module structure
  - Error handling approaches
  - Logging patterns and standards
- Extract common patterns for the feature's domain
- Document anti-patterns to avoid
- Check @project-context for project-specific rules and conventions

**3. Dependency Analysis**

- Catalog external libraries relevant to feature
- Understand how libraries are integrated
- Find relevant documentation in `.cursor/skills/`
- Note library versions and compatibility requirements

**4. Testing Patterns**

- Identify test framework and structure
- Find similar test examples for reference
- Understand test organization (unit vs integration)
- Note coverage requirements and testing standards

**5. Integration Points**

- Identify existing files that need updates
- Determine new files that need creation and their locations
- Map router/API registration patterns
- Understand database/model patterns if applicable

**Clarify Ambiguities:**

- If requirements are unclear, ask the user to clarify before continuing
- Get specific implementation preferences (libraries, approaches, patterns)
- Resolve architectural decisions before proceeding

### Phase 3: External Research & Documentation

**Documentation Gathering:**

- Research latest library versions and best practices
- Find official documentation with specific section anchors
- Locate implementation examples and tutorials
- Identify common gotchas and known issues

**Compile Research References:**

```markdown
## Relevant Documentation

- [Library Official Docs](https://example.com/docs#section)
  - Specific feature implementation guide
  - Why: Needed for X functionality
```

### Phase 4: Strategic Thinking

**Think Harder About:**

- How does this feature fit into the existing architecture?
- What are the critical dependencies and order of operations?
- What could go wrong? (Edge cases, race conditions, errors)
- How will this be tested comprehensively?
- What performance implications exist?
- Are there security considerations?
- How maintainable is this approach?

### Phase 5: Plan Structure Generation

Create comprehensive plan with the following structure:

---

````markdown
# Feature: <feature-name>

## Feature Description

<Detailed description of the feature, its purpose, and value to users>

## User Story

As a <type of user>
I want to <action/goal>
So that <benefit/value>

## Problem Statement

<Clearly define the specific problem this feature addresses>

## Solution Statement

<Describe the proposed solution approach>

## Feature Metadata

**Feature Type**: [New Capability/Enhancement/Refactor/Bug Fix]
**Estimated Complexity**: [Low/Medium/High]
**Primary Systems Affected**: [List of main components/services]
**Dependencies**: [External libraries or services required]

---

## CONTEXT REFERENCES

### Relevant Codebase Files (READ THESE BEFORE IMPLEMENTING)

- `path/to/file.ts` (lines X-Y) - Why: Contains pattern for X
- `path/to/model.ts` - Why: Database model structure to follow

### New Files to Create

- `path/to/new_service.ts` - Service implementation for X
- `tests/path/to/test.ts` - Unit tests for new service

### Relevant Documentation

- [Documentation Link](https://example.com/doc#section)
  - Why: Required for implementing X

### Patterns to Follow

<Specific patterns extracted from codebase>

---

## IMPLEMENTATION PLAN

### Phase 1: Foundation

<Foundational work needed>

### Phase 2: Core Implementation

<Main implementation work>

### Phase 3: Integration

<How feature integrates with existing functionality>

### Phase 4: Testing & Validation

<Testing approach>

---

## STEP-BY-STEP TASKS

### Task Format

- **CREATE**: New files or components
- **UPDATE**: Modify existing files
- **ADD**: Insert new functionality
- **MIRROR**: Copy pattern from elsewhere

### 1. {ACTION} {target_file}

- **IMPLEMENT**: {Specific detail}
- **PATTERN**: {Reference to existing pattern}
- **VALIDATE**: `{validation command}`

---

## TESTING STRATEGY

### Unit Tests

<Scope and requirements>

### Integration Tests

<Scope and requirements>

### Edge Cases

<List specific edge cases>

---

## VALIDATION COMMANDS

### Level 1: Linting & Types

```bash
pnpm lint
pnpm typecheck
```
````

### Level 2: Tests

```bash
pnpm test
```

````

### Level 3: Manual Validation

<Feature-specific manual testing steps>

---

## ACCEPTANCE CRITERIA

- [ ] Feature implements all specified functionality
- [ ] All validation commands pass
- [ ] Code follows project conventions
- [ ] No regressions in existing functionality

---

## COMPLETION CHECKLIST

- [ ] All tasks completed in order
- [ ] All validation commands pass
- [ ] Manual testing confirms feature works
- [ ] Acceptance criteria all met

```

---

## Output Format

### Directory Structure (Preferred)

Plans are organized in feature directories to support iterations:

```
.cursor/plans/{feature-name}/
  ├── agent-session.json    # State tracking (gitignored)
  ├── plan-v1.md            # Initial plan
  ├── plan-v2.md            # After feedback (if iterated)
  └── plan-v3.md            # Further iterations
```

**Directory**: `.cursor/plans/{kebab-case-feature-name}/`
**Plan File**: `plan-v{version}.md` (start with v1)

Examples:
- `.cursor/plans/add-user-authentication/plan-v1.md`
- `.cursor/plans/implement-search-api/plan-v1.md`

### Session State File

When running standalone, create `agent-session.json` in the feature directory:

```json
{
  "feature": "add-user-authentication",
  "description": "Add OAuth authentication with Google and GitHub",
  "currentVersion": 1,
  "status": "awaiting-feedback",
  "created": "2026-02-03T10:30:00Z",
  "lastUpdated": "2026-02-03T10:30:00Z",
  "iterations": [
    { "version": 1, "feedback": null }
  ]
}
```

### Iteration Plans (v2+)

When creating iteration plans, start with a "Changes from Previous" section:

```markdown
## Changes from Previous Version

**Feedback Incorporated**: {user feedback that prompted this iteration}

### What Changed
- {Change 1}
- {Change 2}

### What Stayed the Same
- {Unchanged aspect 1}

---

{Rest of plan follows normal structure}
```

### Legacy Flat File Format (Deprecated)

For backwards compatibility, flat files still work: `.cursor/plans/{kebab-case-feature-name}.md`

However, the directory structure is preferred for new plans.

## Quality Criteria

### Context Completeness ✓
- [ ] All necessary patterns identified and documented
- [ ] External library usage documented with links
- [ ] Integration points clearly mapped
- [ ] Every task has executable validation command

### Implementation Ready ✓
- [ ] Another developer could execute without additional context
- [ ] Tasks ordered by dependency (execute top-to-bottom)
- [ ] Each task is atomic and independently testable

### Pattern Consistency ✓
- [ ] Tasks follow existing codebase conventions
- [ ] No reinvention of existing patterns or utils
- [ ] Testing approach matches project standards

## Success Metrics

**One-Pass Implementation**: Execution can complete feature without additional research

**Confidence Score**: Rate 1-10 likelihood execution will succeed on first attempt

## Report

After creating the plan, provide:

- Summary of feature and approach
- Full path to created plan file
- Complexity assessment
- Key implementation risks
- Confidence score for one-pass success
```

## Execution Handoff

**CRITICAL: Do NOT execute the plan in this agent context.**

After the plan is created and saved:

1. **End this planning session** - Your work is complete
2. **Instruct the user** to execute in a fresh context:
   ```
   To execute this plan, start a new chat and run:
   /implementation/execute .cursor/plans/{feature-name}/plan-v1.md
   ```

**Why separate contexts?**
- Planning and execution are distinct cognitive modes
- Fresh context prevents planning artifacts from influencing implementation
- Execution agent benefits from reading the plan without prior conversation bias
- Cleaner separation of concerns and easier debugging

**Never ask:** "Would you like me to execute this plan now?"
**Always say:** "To execute, start a new chat with `/implementation/execute .cursor/plans/{feature-name}/plan-v{N}.md`"

### Alternative: Orchestrated Workflow

For automated plan→execute→iterate cycles, use the orchestrator command instead:
```
/implementation/implement {feature description}
```

This spawns subagents for planning and execution, managing state automatically.
````
