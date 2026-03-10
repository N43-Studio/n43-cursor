> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Cross-system gap analysis requires comparing project metadata, issue hygiene, and automation contract requirements -->

# Audit Linear Project for Ralph

Audit a Linear project against the n43-cursor Ralph workflow contract and produce a risk report.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `mode=read-only|propose-fixes` (default: `read-only`)

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

### C. Label Taxonomy + Readiness

1. Required labels exist:
   - `Ralph`
   - `PRD Ready`
   - `Human Required`
2. `Agent Generated` is treated as provenance metadata (recommended for generated issues, not a readiness gate).
3. Issues intended for automation satisfy readiness semantics:
   - include `Ralph`
   - include `PRD Ready`
   - do **not** include `Human Required`

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

1. Required claim labels exist:
   - `Ralph Queue`
   - `Ralph Claimed`
   - `Ralph Completed`
   - `Human Required`
2. Claimed issues (`Ralph Claimed`) have exactly one active owner (`assignee` preferred, `delegate` allowed).
3. No claim collisions:
   - same issue claimed by conflicting owners
   - issue marked `Ralph Claimed` and `Human Required` at the same time
4. Stale-claim recovery readiness:
   - stale definition: `In Progress` + `Ralph Claimed` + no owner heartbeat/update for 24h
   - recovery action documented: unclaim + requeue only if readiness gate passes

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
3. Low-confidence metadata is at least `major` when the issue is marked `PRD Ready`.
4. Recommend rescoring via `scripts/score-issue-metadata.sh` when metadata drift is detected.

## Process

1. Read project + issues + statuses + labels via Linear MCP.
2. Run all audit checks.
3. Produce a severity-ranked gap report:
   - `critical`: blocks `/ralph/run`
   - `major`: likely runtime issues
   - `minor`: quality/maintainability risks
4. If `mode=propose-fixes`, provide exact follow-up commands and payloads.

## Output Format

Return:

1. **Summary**: ready/not-ready for Ralph
2. **Findings**: ordered by severity with evidence
3. **Fix Plan**: concrete next commands (`/linear/create-project`, `/linear/populate-project`, `/linear/generate-prd-from-project`, `/ralph/run`)

## Safety

- `read-only` mode must not create/update Linear entities.
- `propose-fixes` mode still does not auto-apply; it only proposes explicit actions.
