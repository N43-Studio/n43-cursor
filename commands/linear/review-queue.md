> **Recommended Model**: Tier 1 - Claude 4.6 Opus

<!-- **Why**: Requires deterministic triage + lifecycle-safe state transitions across multiple issues -->

# Review Linear Queue (`Needs Review` + `Needs Human`)

Process a deterministic queue of review candidates and apply auditable comment + state transitions.

## Input

`$ARGUMENTS` supports:

- `project=<project-id-or-name>` (required)
- `team=<team-key-or-name>` (optional, default `Studio`)
- `mode=read-only|propose-fixes|apply` (default: `read-only`)

Examples:

```text
/linear/review-queue project="Ralph Wiggum Flow"
/linear/review-queue project="Ralph Wiggum Flow" mode=apply
```

## Candidate Selection

Select issues where either condition is true:

1. state is `Needs Review`
2. labels include `Needs Human` or `Human Required`

Order candidates deterministically:

1. priority ascending (`1` first)
2. updatedAt ascending
3. issue identifier ascending

## Deterministic Decision Matrix

For each candidate, pick exactly one decision:

- `accepted` -> transition to `Reviewed`
- `rework_required` -> transition to `In Progress`
- `canceled` -> transition to `Canceled`
- `blocked_needs_input` -> remain/return to `Needs Review`

## Required Review Comment

For every processed issue, post a structured comment:

1. `What Was Reviewed`
2. `Decision`
3. `Rationale`
4. `Next Step`

Optional:

- `Validation Evidence`
- `Owner`
- `Due / Follow-up Window`

## Process

1. Read project issues + statuses + labels via Linear MCP.
2. Build deterministic candidate queue.
3. Run review triage for each issue and compute decision.
4. In `mode=read-only`, output planned comments/transitions only.
5. In `mode=propose-fixes`, output exact Linear MCP actions.
6. In `mode=apply`, for each candidate:
   - post review comment
   - transition issue state per decision matrix
   - record success/failure in run summary

## Output Format

Return:

1. **Summary**: candidates processed + transition counts by decision
2. **Issue Decisions**: ordered list with rationale per issue
3. **Applied Actions** (for `mode=apply`): comment id + state transition result per issue
4. **Failures**: issues where comment/transition failed with next remediation step

## Safety

- Never do silent transitions; comments are mandatory for every processed issue.
- If state transition fails after comment post, add a follow-up failure note and keep issue visible in output.
- Use `contracts/ralph/core/review-queue-contract.md` as canonical behavior source.
