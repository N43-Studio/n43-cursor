> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Cross-system gap analysis requires comparing project metadata, issue hygiene, and automation contract requirements -->

# Audit Linear Project for Ralph

Audit a Linear project against the n43-cursor Ralph workflow contract and produce a risk report.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `mode=read-only|propose-fixes` (default: `read-only`)
- `preflight_question_scan=true|false` (default: `true`)

Examples:

```text
/linear/audit-project project="Ralph Wiggum Flow"
/linear/audit-project project="Ralph Wiggum Flow" mode=propose-fixes
```

## Audit Checks

### A. Project Health

1. Project exists and resolves unambiguously.
2. Team mapping is valid.
3. Target dates, lead, and description are present.

### B. Issue Readiness for Ralph

1. Issue count > 0.
2. Each issue has:
   - title
   - non-empty description
   - priority
   - valid state
3. Dependencies are represented consistently.
4. Issue identifiers map cleanly to PRD `issueId`.
5. Metadata quality from `contracts/ralph/core/issue-metadata-rubric.md`:
   - `priority` and `estimate` are present
   - issue body includes a `Metadata Rationale` section (or equivalent deterministic rubric trace)
   - low-confidence metadata (`confidence < 0.60`) is explicitly called out
6. Decomposition safety for superseded umbrellas:
   - replacement slices are not modeled as sub-issues of a soon-to-be-terminal umbrella issue
   - replacement slices are runnable before umbrella terminalization
   - superseded umbrella closure policy prefers `Done` over `Canceled` while replacements remain active

### C. Structural Readiness + Label Taxonomy

1. Structural readiness checks are evaluated per issue:
   - description is non-empty
   - includes `Goal` or `Context`
   - includes `Scope` or implementation-plan details
   - includes acceptance criteria heading/checklist
   - includes validation section/checks
   - includes metadata rationale or explicit `priority` + `estimate` signals
2. `Human Required` remains a hard exclusion for unattended execution.
3. `Agent Generated` is treated as provenance metadata (recommended for generated issues, not a readiness gate).
4. Migration compatibility labels are audited explicitly:
   - `Ralph` + `PRD Ready` may admit readiness only as temporary fallback when structural checks are missing
   - audit output must identify each fallback-admitted issue and missing structural signals

### D. Status Mapping

Validate status semantics against `contracts/ralph/core/status-semantics.md`:

1. Team has unambiguous mappings for:
   - `In Progress`
   - `Needs Review`
   - `Reviewed`
   - terminal completion state (`Done`)
2. New-work selection exclusions are explicit:
   - `Triage`
   - `Needs Review`
   - terminal states (`Done`, `Canceled`)
3. Review-cycle semantics are explicit:
   - `Needs Review` -> `Reviewed`
   - `Reviewed` either:
     - final completion path, or
     - deterministic requeue path for rework
4. Flag ambiguous/missing mappings as `critical` for automation safety.

### E. Claim Protocol Safety

1. Canonical active claims are evaluated from status/owner state:
   - `In Progress` implies an active claim
   - exactly one active owner (`assignee` preferred, `delegate` allowed)
   - `Human Required` remains the canonical blocked-human label
2. Deprecated claim labels are compatibility-only:
   - `Ralph Queue`
   - `Ralph Claimed`
   - `Ralph Completed`
   - absence is not a failure
   - if present, they must not contradict canonical status/owner state
3. No claim collisions:
   - same issue claimed by conflicting owners
   - issue marked active and `Human Required` at the same time without explicit blocked-hand-off intent
   - issue carries legacy `Ralph Claimed` while canonical state is not active
4. Stale-claim recovery readiness:
   - stale definition: `In Progress` + active owner or legacy `Ralph Claimed` + no owner heartbeat/update for 24h
   - recovery action documented: unclaim + restore readiness only if readiness gate passes

### E2. Claim Label Deprecation Report

Flag deprecated claim-label usage and contradictions per `contracts/ralph/core/claim-label-deprecation.md`:

1. List every issue that still carries any deprecated claim label (`Ralph Queue`, `Ralph Claimed`, `Ralph Completed`).
2. For each labeled issue, report:
   - whether structural readiness is already satisfied (label is fully redundant)
   - whether canonical status/owner state agrees with the label (e.g., `Ralph Claimed` implies `In Progress` + owner)
   - contradiction severity:
     - `critical`: `Ralph Claimed` present without an active owner or while status is not `In Progress`
     - `major`: `Ralph Completed` present but issue status is not terminal (`Done` / `Canceled`)
     - `minor`: `Ralph Queue` present on a structurally-ready issue (redundant but harmless)
3. Recommend removal of deprecated labels where structural readiness and canonical claim state are both satisfied.
4. When `mode=propose-fixes`, include exact label-removal payloads per issue.

Absence of deprecated claim labels is never a finding. Only their presence triggers this report section.

### F. Ambiguity + Resume Safety

1. For issues labeled `Human Required`, verify a structured handoff comment exists with all sections:
   - `Assumptions Made`
   - `Questions for Human`
   - `Impact if Assumptions Are Wrong`
   - `Proposed Revision Plan After Answer`
2. Verify resumability policy is documented:
   - issue remains visible in `In Progress` + `Human Required` while awaiting answers
   - revision run resumes on same branch after human response

### G. PRD Compatibility

Confirm project data can produce PRD with:

- `branchName`
- `issues[]`
- `issueId`, `title`, `description`, `priority`, `passes`
- optional but recommended: `estimatedTokens`
- `sourceLinearSnapshot.hash` for freshness safety in `/ralph/run`

If not, provide exact transformation gaps.

### H. Metadata Consistency

Validate deterministic metadata hygiene for planning and scheduling:

1. Missing `priority` or `estimate` is at least `major`.
2. Missing metadata rationale is at least `minor`.
3. Low-confidence metadata is at least `major` when the issue is structurally ready or admitted via migration fallback labels.
4. Recommend rescoring via `scripts/score-issue-metadata.sh` when metadata drift is detected.

### I. Deterministic Scheduling Inputs

Validate that `/ralph/run` can make deterministic picks without ambiguity:

1. Runnable issues have explicit `priority` values in Linear range (`1..4`).
2. Runnable issues have deterministic estimate values (`1/2/3/5/8` preferred).
3. Readiness diagnostics are explicit for runnable scope:
   - `readiness_source` is `structural` or `label_migration`
   - structural pass/fail reasons are recorded
   - `Human Required` exclusions are explicit
4. Status values are mappable to runnable/non-runnable semantics from `contracts/ralph/core/status-semantics.md`.
5. Flag ambiguous scheduling input combinations as `major` or `critical` when they can reorder execution unpredictably.

### J. Preflight Human-Question Scan

When `preflight_question_scan=true`, scan project issues using `contracts/ralph/core/preflight-question-scan-rubric.md`:

1. `Open Human Questions`:
   - explicit unresolved questions in issue descriptions/comments
   - unresolved decision markers (`Questions`, `Unknowns`, `Decision Needed`, unresolved TODOs)
2. `Potential Human Questions`:
   - missing decision-critical detail (scope boundaries, acceptance ambiguity, dependency ownership, rollout constraints)
   - signals that subjective product/engineering judgment is likely required
3. `Issues Safe for Unattended Execution`:
   - no unresolved `critical`/`major` question risk
   - readiness semantics still satisfied (structural readiness pass, no `Human Required`; migration fallback must be called out when used)
4. `Recommended Human-Answer Queue (ordered by risk)`:
   - `critical` -> `major` -> `minor`
   - stable tiebreak by dependency fan-out then `issueId`
5. For `critical` and `major` findings, include suggested question drafts suitable for Linear comments.

## Process

1. Read project + issues + statuses + labels via Linear MCP.
2. Run all audit checks.
3. If `preflight_question_scan=true`, run deterministic question-risk scan and build the human-answer queue.
4. Produce a severity-ranked gap report:
   - `critical`: blocks `/ralph/run`
   - `major`: likely runtime issues
   - `minor`: quality/maintainability risks
5. If `mode=propose-fixes`, provide exact follow-up commands and payloads.

## Output Format

Return:

1. **Summary**: ready/not-ready for Ralph
2. **Findings**: ordered by severity with evidence
3. **Structural Readiness Report**:
   - Per-issue table with:
     - `issueId` and `title`
     - `readiness_source` (`structural`, `label_migration`, or `not_ready`)
     - overall `ready` status (YES / NO)
     - per-check diagnostics: `has_description`, `has_goal_or_context`, `has_scope_signal`, `has_acceptance`, `has_validation`, `has_metadata`, `human_required_absent`
   - Summary counts: structurally ready, label-migration-only, not ready
   - Issues admitted only via label-migration fallback carry a **deprecation warning**:
     > ⚠ DEPRECATION: This issue is admitted via `Ralph` + `PRD Ready` label fallback only. Add the missing structural headings (Goal/Context, Scope, Acceptance Criteria, Validation, Metadata Rationale) to the issue description to satisfy structural readiness before label fallback is removed.
   - Recommendation: run `scripts/check-structural-readiness.sh <prd.json> --format text` for a standalone readiness check outside the full audit
   - Reference: `contracts/ralph/core/structural-readiness-checklist.md` for operator guidance on satisfying each check
4. **Claim Label Deprecation Report** (when deprecated labels are present):
   - issues carrying deprecated claim labels
   - per-issue contradiction severity and recommendation
   - label-removal payloads (when `mode=propose-fixes`)
5. **Preflight Question Scan** (when enabled):
   - `Open Human Questions`
   - `Potential Human Questions`
   - `Issues Safe for Unattended Execution`
   - `Recommended Human-Answer Queue (ordered by risk)`
   - suggested comment drafts for high-risk unresolved questions
6. **Fix Plan**: concrete next commands (`/linear/create-project`, `/linear/populate-project`, `/linear/generate-prd-from-project`, `/ralph/run`)

## Safety

- `read-only` mode must not create/update Linear entities.
- `propose-fixes` mode still does not auto-apply; it only proposes explicit actions.
- Preflight scan semantics must follow `contracts/ralph/core/preflight-question-scan-rubric.md`.
