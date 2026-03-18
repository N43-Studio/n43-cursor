# Preflight Question-Scan Rubric

## Goal

Detect unresolved human-decision risk before unattended Ralph execution so ambiguity is addressed during staffed hours.

## Output Sections

`/linear/audit-project` preflight scan must produce:

- `Open Human Questions`
- `Potential Human Questions`
- `Issues Safe for Unattended Execution`
- `Recommended Human-Answer Queue (ordered by risk)`

## Detection Rules

### Open Human Questions

Classify as open when issue evidence includes explicit unresolved prompts, for example:

- direct questions (`?`) tied to implementation decisions
- TODO markers with human owner not assigned
- comments/description blocks labeled `Questions`, `Unknowns`, `Decision Needed`

### Potential Human Questions

Classify as potential when decision-critical detail is missing and assumptions are likely:

- scope boundaries unclear
- acceptance criteria ambiguity
- dependency owner missing
- rollout/operational constraints unspecified
- subjective product/UX tradeoff not decided

## Risk Scoring

Each finding must include a deterministic risk level:

- `critical`: unattended execution should be blocked
- `major`: unattended execution should warn and require explicit override
- `minor`: unattended execution allowed, but resolution recommended

Risk scoring factors:

- user-facing impact if assumption is wrong
- likelihood of rework/rollback
- dependency fan-out
- compliance/security/availability sensitivity

## Human-Answer Queue

Queue entries must include:

- `issueId`
- `riskLevel`
- `rationale`
- `questionDraft` (ready-to-post Linear comment text)
- `impactIfUnanswered`

Queue ordering:

1. `critical` before `major` before `minor`
2. higher dependency fan-out first
3. stable tiebreak by `issueId`

## Safe/Unsafe Classification

`Issues Safe for Unattended Execution` requires:

- no unresolved `critical` or `major` question findings
- readiness semantics satisfied (structural readiness pass, no `Human Required`; migration fallback labels are explicitly flagged when used)

Issues not meeting these criteria must be classified unsafe until questions are resolved or explicit override is documented.
