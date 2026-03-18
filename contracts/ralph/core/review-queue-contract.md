# Review Queue Contract

## Intent

Define a deterministic Linear review flow for issues in `Needs Review` state or labeled `Needs Human`/`Human Required`.

This queue is the canonical async review path for `independent` workflow mode. `human-in-the-loop` mode should avoid entering this queue for mid-execution clarification/review.

## Candidate Selection

Candidates are issues matching either condition:

- state is `Needs Review`
- labels include `Needs Human` or `Human Required`

Selection ordering must be deterministic:

1. priority ascending (`1` first)
2. updatedAt ascending (oldest waiting first)
3. issue identifier ascending

## Deterministic Decision Outcomes

Each reviewed candidate maps to exactly one outcome:

- `accepted` -> transition to `Reviewed`
- `rework_required` -> transition to `In Progress`
- `canceled` -> transition to `Canceled`
- `blocked_needs_input` -> remain/return to `Needs Review`

## Required Review Comment Schema

Every processed issue must receive a structured comment with:

- `What Was Reviewed`
- `Decision`
- `Rationale`
- `Next Step`

Optional but recommended:

- `Validation Evidence`
- `Owner`
- `Due / Follow-up Window`

## Auditability Rules

- Do not perform silent state transitions.
- Comment and state transition must be recorded in the same processing pass.
- When transition fails, post a failure note and keep current state unchanged.

## Status/Lifecycle Alignment

This contract extends `status-semantics.md` review-cycle behavior and keeps requeue behavior compatible with `review-feedback-sweep-contract.md`.
