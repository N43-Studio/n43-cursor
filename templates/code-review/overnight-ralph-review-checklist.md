# Overnight Ralph Review Checklist

## Correctness

- [ ] Acceptance criteria in each executed issue still match the implemented behavior.
- [ ] No cross-issue regressions are introduced by overlapping file changes.
- [ ] Failure summaries in result JSON match observed repository state.

## Test Coverage

- [ ] Required validations (`lint`, `typecheck`, `test`, `build`) are pass/skipped with explicit rationale.
- [ ] New or changed behavior has deterministic test coverage or an explicit follow-up issue.
- [ ] Any skipped checks are triaged with owner and due date.

## Rollback Safety

- [ ] High-risk changes have a clear rollback or revert path.
- [ ] Breaking config/contract changes are identified before merge.
- [ ] Rollback instructions are documented for operationally sensitive updates.

## Security

- [ ] Auth, secret handling, and permission boundaries were not weakened.
- [ ] New scripts/automation avoid unsafe command execution patterns.
- [ ] Security-sensitive deltas are reviewed first in the triage queue.

## Docs Drift

- [ ] Commands/contracts/docs changed by Ralph stay aligned.
- [ ] User-facing command references match current file paths and names.
- [ ] Any required follow-up documentation updates are explicitly tracked.

## Decision Log

- [ ] Triage decision recorded for every non-success outcome.
- [ ] Owners assigned for follow-up actions and retry/handoff work.
- [ ] Final review disposition documented (`approve`, `needs changes`, or `hold`).
