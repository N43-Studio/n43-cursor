# Ralph Reference

Ralph takes a Linear project and executes its issues one-by-one through AI agents, handling dependency ordering, status transitions, commits, and retrospectives.

For a quick overview and when to use Ralph vs. the standard workflow, see the [Suggested Developer Workflow](../README.md#suggested-developer-workflow) in the main README. For the underlying package architecture (contracts, engine, executor interface), see the [ralph repo](https://github.com/N43-Studio/ralph).

---

## Table of Contents

- [Execution Surfaces](#execution-surfaces)
- [Setup: Fast Path](#setup-fast-path)
- [Setup: Manual Path](#setup-manual-path)
- [Issue Authoring Requirements](#issue-authoring-requirements)
- [Swapping the Execution Backend](#swapping-the-execution-backend)
- [Worktree Management](#worktree-management)
- [Overnight Review Playbook](#overnight-review-playbook)
- [Linear Workflow Commands](#linear-workflow-commands)
- [Dual-Surface Bootstrap](#dual-surface-bootstrap)
- [Drift Checks](#drift-checks)

---

## Execution Surfaces

| Surface | Command | Codex CLI Required? |
| ------- | ------- | ------------------- |
| **Cursor** (recommended) | `/ralph/run` slash command | No |
| **Terminal** | `scripts/ralph-run.sh --prd <path>` | Yes |
| **Terminal (dry run)** | `RALPH_ISSUE_EXECUTOR_CMD=scripts/mock-issue-agent.sh scripts/ralph-run.sh --prd <path>` | No |

> The Codex CLI is only required for terminal-based execution. The Cursor `/ralph/run` command works entirely within Cursor's agent system.

## Setup: Fast Path

In Cursor, run:

```
/ralph/build
```

This chains: create Linear project → populate with issues → generate PRD → audit readiness. Then:

```
/ralph/run
```

## Setup: Manual Path

For more control over each step:

```
/linear/create-project       # define the project + milestones
/linear/populate-project     # generate issues from project scope
/linear/generate-prd-from-project   # export to prd.json
/linear/audit-project        # validate readiness (optional but recommended)
/ralph/run prd=.cursor/ralph/<project-slug>/prd.current.json
```

## Issue Authoring Requirements

Every issue Ralph executes must have four sections in its description:

| Section | Purpose |
| ------- | ------- |
| `## Goal` | What the issue achieves |
| `## Context` | Relevant background and constraints |
| `## Acceptance Criteria` | Checklist of done conditions |
| `## Validation` | How to verify the work (commands, checks) |

Issues missing these sections will fail structural readiness and be skipped. The `/linear/populate-project` command generates issues in this format automatically.

See `contracts/ralph/core/readiness-taxonomy.md` for full readiness criteria.

## Swapping the Execution Backend

The terminal-based flow uses `scripts/configured-issue-agent.sh`, which delegates to a configurable backend via the `RALPH_ISSUE_EXECUTOR_CMD` environment variable:

```bash
# Default: Codex CLI
scripts/ralph-run.sh --prd prd.json

# Custom backend
RALPH_ISSUE_EXECUTOR_CMD=my-custom-agent.sh scripts/ralph-run.sh --prd prd.json

# Smoke test (no-op agent, always succeeds)
RALPH_ISSUE_EXECUTOR_CMD=scripts/mock-issue-agent.sh scripts/ralph-run.sh --prd prd.json
```

Any backend must implement the CLI issue execution contract: read `--input-json`, write `--output-json` with the result schema defined in `contracts/ralph/core/cli-issue-execution-contract.md`.

## Worktree Management

Ralph uses isolated git worktrees for parallel issue execution via `scripts/ralph-worktree.sh`:

```bash
scripts/ralph-worktree.sh create --issue N43-477
scripts/ralph-worktree.sh list
scripts/ralph-worktree.sh prune --issue N43-477
```

**Naming defaults:**

| Item | Path |
| ---- | ---- |
| Worktree root | `.ralph/worktrees/` |
| Worktree path | `.ralph/worktrees/<issue-slug>` |
| Branch | `ralph/worktree/<issue-slug>` |

Conflict cases (branch already checked out elsewhere, dirty worktree removal) return explicit JSON with `status="conflict"`, `conflict_reason`/`conflicts`, and escalation guidance.

## Overnight Review Playbook

For unattended overnight runs, two complementary tools generate human-readable review artifacts:

**Morning briefing:**
- `commands/ralph/morning-briefing.md` + `scripts/generate-morning-briefing.sh`
- Generates deterministic markdown/JSON from `run-log.jsonl`, retrospective output, and PRD artifacts

**Review context:**
- `commands/code-review/prepare-overnight-ralph-review.md` + `scripts/prepare-overnight-review.sh`
- Generates a review context doc from `progress.txt`, `run-log.jsonl`, and `.ralph/results/*-result.json`

**Templates:** `templates/code-review/overnight-ralph-review-context.md` and `overnight-ralph-review-checklist.md`

### Triage SLA

| Triage Bucket | Trigger Examples | Acknowledge | Action Target |
| ------------- | ---------------- | ----------- | ------------- |
| `critical` | security risk, data-loss path, broken contract | 30 min | mitigation plan within 2 hours |
| `high` | `human_required`, non-retryable failure, rollback uncertainty | 2 hours | owner + plan same business day |
| `normal` | successful outcomes, skipped checks, docs drift | same day | closure or follow-up within 1 business day |

## Linear Workflow Commands

| Command | Purpose |
| ------- | ------- |
| `/linear/create-project` | Create a new Linear project with description and milestones |
| `/linear/populate-project` | Generate dependency-aware issues from project scope |
| `/linear/generate-prd-from-project` | Export project issues to `prd.json` |
| `/linear/audit-project` | Audit project consistency and risk before execution |

**Expected flow:** `create-project` → `populate-project` → `generate-prd-from-project` → `ralph/run`

**Single-entry alternative:** `/ralph/build` → `/ralph/run`

## Dual-Surface Bootstrap

For Ralph workflow links across both Cursor and Codex surfaces:

```bash
scripts/bootstrap-ralph-surfaces.sh install
scripts/bootstrap-ralph-surfaces.sh verify
```

This manages:
- Cursor links in `.cursor/` for `agents`, `commands`, `rules`, and `skills`
- Codex links in `$CODEX_HOME/skills` (or `~/.codex/skills`) for Ralph skill wrappers

Verification output includes deterministic markers: `RESULT_SUMMARY` with link counts, `RESULT PASS` or `RESULT FAIL`.

## Drift Checks

Run local guardrails for cross-surface parity and terminology drift:

```bash
scripts/check-ralph-drift.sh
```

CI runs the same guardrail via `.github/workflows/ralph-drift-checks.yml`.
