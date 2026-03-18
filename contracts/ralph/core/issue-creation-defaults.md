# Issue Creation Defaults Contract

## Purpose

Define the default metadata fields, label set, and heuristics applied to all agent-created Ralph issues. This contract ensures that issues created by any agent surface (populate-project, create-issue, retrospective follow-ups, issue decomposition) land with sufficient metadata for deterministic scheduling — without requiring a manual normalization pass.

## Required Sections

Every agent-created issue body must include these structural sections to satisfy the readiness taxonomy (`readiness-taxonomy.md`):

| Section | Required | Notes |
|---------|----------|-------|
| `## Goal` | Yes | One paragraph describing the intended outcome |
| `## Context` | Recommended | Why this matters; constraints |
| `## Implementation Notes` or `## Scope` | Yes | Scope, expected files, non-goals, edge cases |
| `## Acceptance Criteria` | Yes | Checklist of verifiable criteria |
| `## Validation` | Yes | At minimum: `lint`, `typecheck`, `test`, `build` |
| `## Metadata Rationale` | Yes | See fields below |

Reference template: `templates/linear/prd-ready-issue.md`.

## Metadata Rationale Fields

The `## Metadata Rationale` section must include the following fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `priority` | integer (1–4) | Yes | Linear priority value with label and justification |
| `estimate` | integer (1–5) | Yes | Issue point estimate with justification |
| `estimatedTokens` | integer | Yes | Projected input+output tokens for implementation |
| `confidence` | float (0.0–1.0) | Yes | Scope-clarity confidence score |
| `lowConfidence` | boolean | Yes | `true` when confidence triggers human review |
| `rubricFactors` | JSON object | Recommended | Scorer signal inputs, or `{}` when scored manually |

### Priority Labels

| Value | Label | Typical Use |
|-------|-------|-------------|
| 1 | Urgent | Blocks active automation; critical path |
| 2 | High | Blocks downstream work within the same project |
| 3 | Medium | Standard implementation work |
| 4 | Low | Improvement, cleanup, or deferred work |

### Estimate Heuristics

| Points | Scope |
|--------|-------|
| 1 | Single-file change, config update, template fix |
| 2 | Multi-file change within one module/domain |
| 3 | Cross-module change or new integration point |
| 4 | New subsystem or significant refactor |
| 5 | Large feature spanning multiple subsystems |

## Token Estimation Heuristics

Estimated tokens represent projected total input+output tokens for an agent implementation run. These are planning signals for resource budgeting, not hard limits.

| Issue Type | Estimated Tokens | Rationale |
|------------|-----------------|-----------|
| Config/template fix | 3200 | Narrow scope, minimal context loading |
| Contract/doc update | 4800 | Moderate reading, focused writing |
| Single-script change | 6400 | Standard implementation cycle |
| Multi-file implementation | 9600 | Broader context, more validation |
| Cross-module refactor | 12800 | Wide reading, dependency analysis |
| New subsystem | 16000+ | Full design-implement-validate cycle |

### Severity-Based Defaults (Retrospective Follow-Ups)

When the metadata scorer is unavailable, retrospective follow-ups use severity-based fallbacks:

| Severity | Priority | Estimate | Estimated Tokens | Confidence |
|----------|----------|----------|-----------------|------------|
| critical | 1 | 3 | 9600 | 0.68 |
| major | 2 | 2 | 6400 | 0.68 |

## Confidence Scoring

| Range | Meaning | `lowConfidence` |
|-------|---------|----------------|
| 0.85–1.0 | Well-scoped, clear implementation path | `false` |
| 0.70–0.84 | Mostly clear, minor ambiguity | `false` |
| 0.50–0.69 | Moderate ambiguity, some unknowns | `true` |
| 0.00–0.49 | Significant ambiguity, exploratory | `true` |

### When `lowConfidence` Should Be True

- Scope is ambiguous or underspecified
- Implementation touches undocumented behavior
- Cross-cutting changes spanning multiple unrelated modules
- Dependency on external systems with unclear contracts
- Scope derived from a broad retrospective observation rather than a specific finding
- Metadata was injected by a fallback path (scorer unavailable, intent worker default)

## Default Label Set

### Required Labels (All Agent-Created Issues)

| Label | Purpose | Gate? |
|-------|---------|-------|
| `Ralph` | Domain routing — issue belongs to Ralph automation domain | Readiness (migration fallback) |
| `PRD Ready` | Migration compatibility — required during migration period | Readiness (migration fallback) |
| `Agent Generated` | Provenance — marks agent-created issues | Never a gate |

### Situational Labels

| Label | When to Apply |
|-------|---------------|
| `Improvement` | Retrospective follow-up issues |
| `Human Required` | Blocked on human input; excludes from automation |
| Domain labels (e.g., `workflow`, `contract`) | Based on target area |

### Excluded Labels

Deprecated claim labels must **never** be added to new issues:

- `Ralph Queue` — deprecated per `claim-label-deprecation.md`
- `Ralph Claimed` — deprecated
- `Ralph Completed` — deprecated

## Intent Worker Safety Net

When `scripts/issue-intent-worker.sh` processes an intent whose body is missing `## Metadata Rationale`, it injects a default section with conservative values:

- `priority=3 (Medium)`: insufficient context for deterministic scoring
- `estimate=2`: assumed moderate scope
- `estimatedTokens=6400`: moderate implementation estimate
- `confidence=0.50`: metadata was injected by fallback
- `lowConfidence=true`: review recommended

This ensures every created issue has metadata for scheduling, while the `lowConfidence=true` flag signals that human or scorer review is needed.

## Creation Flow Coverage

| Flow | Metadata Source | Label Source |
|------|----------------|-------------|
| `populate-project` | `scripts/score-issue-metadata.sh` with calibration | Command spec (lines 98–104) |
| `create-issue` | `scripts/score-issue-metadata.sh` with calibration | Readiness taxonomy |
| Retrospective follow-ups | Scorer with severity-based fallback | `LABELS_BASE_CSV` in script |
| Intent worker (fallback) | Default injection when missing | Required label enforcement |

## Related Contracts

- `contracts/ralph/core/readiness-taxonomy.md` — structural readiness and label taxonomy
- `contracts/ralph/core/claim-label-deprecation.md` — deprecated label policy
- `contracts/ralph/core/issue-metadata-rubric.md` — deterministic scoring rubric
- `templates/linear/prd-ready-issue.md` — reference issue template
- `commands/linear/populate-project.md` — primary issue creation command
- `commands/linear/create-issue.md` — single issue creation command
