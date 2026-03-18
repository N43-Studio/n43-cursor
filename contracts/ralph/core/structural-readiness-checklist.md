# Structural Readiness Checklist

Operator reference for the 7 structural readiness checks that gate unattended automation in `ralph-run`.

**Authoritative source**: [`contracts/ralph/core/readiness-taxonomy.md`](readiness-taxonomy.md)

**Tooling**: [`scripts/check-structural-readiness.sh`](../../../scripts/check-structural-readiness.sh)

---

## Check 1: Description Non-Empty

**Signal**: `has_description`

The issue description must contain at least one non-whitespace character.

| Status | Example |
|--------|---------|
| ✔ Pass | `"Refactor the auth middleware to use async/await..."` |
| ✘ Fail | `""` or whitespace-only |

---

## Check 2: Goal or Context Heading

**Signal**: `has_goal_or_context`

The description must include a Markdown H2 heading matching `## Goal` or `## Context`.

| Status | Example |
|--------|---------|
| ✔ Pass | `## Goal\nReplace label-based readiness with structural checks.` |
| ✔ Pass | `## Context\nThe current system relies on deprecated labels...` |
| ✘ Fail | No `## Goal` or `## Context` heading present |

---

## Check 3: Scope or Implementation-Plan Signal

**Signal**: `has_scope_signal`

The description must include a Markdown H2 heading matching one of:
- `## Scope`
- `## Implementation Notes`
- `## Implementation Plan`
- `## Approach`
- `## Non-Goals`
- `## Constraints`

| Status | Example |
|--------|---------|
| ✔ Pass | `## Scope\n1. Update ralph-run.sh\n2. Add standalone checker` |
| ✔ Pass | `## Implementation Notes\nModify the next_issue() jq filter...` |
| ✘ Fail | Implementation details exist but under a non-matching heading like `## Details` |

---

## Check 4: Acceptance Criteria

**Signal**: `has_acceptance` (satisfied by either `has_acceptance_heading` or `has_acceptance_checklist`)

The description must include **at least one** of:
- A `## Acceptance Criteria` heading
- A Markdown checklist item: `- [ ] ...` or `- [x] ...` or `* [ ] ...`

| Status | Example |
|--------|---------|
| ✔ Pass | `## Acceptance Criteria\n- [ ] Standalone readiness checker script exists` |
| ✔ Pass | `- [ ] Audit output includes per-issue diagnostics` (checklist without heading) |
| ✘ Fail | Acceptance criteria described in prose without heading or checklist syntax |

---

## Check 5: Validation Expectations

**Signal**: `has_validation` (satisfied by either `has_validation_heading` or `has_validation_checks`)

The description must include **at least one** of:
- A `## Validation` heading
- Inline validation check references matching: `` `lint` ``, `` `typecheck` ``, `` `test` ``, or `` `build` `` followed by `:` or `-`

| Status | Example |
|--------|---------|
| ✔ Pass | `## Validation\n- lint: pnpm lint passes\n- test: pnpm test passes` |
| ✔ Pass | `- \`lint\`: no new warnings\n- \`build\`: compiles cleanly` |
| ✘ Fail | `Tests should pass` (no heading, no structured check references) |

---

## Check 6: Metadata Rationale

**Signal**: `has_metadata` (satisfied by either `has_metadata_section` or `has_metadata_values`)

The description must include **at least one** of:
- A `## Metadata Rationale` heading
- Inline `priority:` **and** `estimate:` (or `estimatedpoints:`) signals

| Status | Example |
|--------|---------|
| ✔ Pass | `## Metadata Rationale\nPriority 2 — medium complexity, no blocking deps.` |
| ✔ Pass | `priority: 2\nestimate: 3` |
| ✘ Fail | Priority and estimate set only in Linear fields with no description-level rationale |

---

## Check 7: Human Required Absent

**Signal**: `human_required_absent`

The issue must **not** carry a `Human Required` label. This is a hard exclusion — issues needing human input are never eligible for unattended execution regardless of other checks.

| Status | Example |
|--------|---------|
| ✔ Pass | No `Human Required` label on the issue |
| ✘ Fail | Issue has `Human Required` label (blocked for human input) |

---

## Quick Reference Table

| # | Check | Required Heading / Signal | Alternatives |
|---|-------|--------------------------|-------------|
| 1 | Description non-empty | Any non-whitespace content | — |
| 2 | Goal or Context | `## Goal` or `## Context` | — |
| 3 | Scope signal | `## Scope` | `## Implementation Notes`, `## Approach`, `## Non-Goals`, `## Constraints` |
| 4 | Acceptance criteria | `## Acceptance Criteria` | Markdown checklist `- [ ] ...` |
| 5 | Validation | `## Validation` | Inline `` `lint` ``/`` `typecheck` ``/`` `test` ``/`` `build` `` checks |
| 6 | Metadata rationale | `## Metadata Rationale` | Inline `priority:` + `estimate:` |
| 7 | Human Required absent | No `Human Required` label | — |

---

## Running the Checker

```bash
# Check all issues in a PRD
scripts/check-structural-readiness.sh prd.json --format text

# Check a single issue
scripts/check-structural-readiness.sh --issue '{"issueId":"N43-100","title":"...","description":"...","labels":[]}' --format json

# Pipe from stdin
cat prd.json | scripts/check-structural-readiness.sh --stdin --format text
```

---

## Migration from Label-Based Readiness

Issues currently admitted via `Ralph` + `PRD Ready` labels (the `label_migration` path) should be updated to satisfy all 7 structural checks. Once structural readiness passes, the label fallback is no longer needed.

See [readiness-taxonomy.md § Backlog Migration Policy](readiness-taxonomy.md) for the full migration plan and timeline.
