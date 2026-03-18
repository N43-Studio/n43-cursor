> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Orchestrates deterministic stages with structured output; no deep reasoning needed -->

# Run Project Closeout

Compose all 6 closeout stages into a single operator-facing closeout packet. Takes a long-lived Ralph branch from iterative development to a coherent, reviewable, merge-ready end state.

## When to Use

Run this command when a Ralph project branch has reached feature-complete and needs to transition from "working state" to "shippable state." Typical triggers:

- All PRD issues are `Done`
- The branch has diverged significantly from `main` (10+ commits, many changed files)
- Transient runtime artifacts have accumulated (`.ralph/`, `progress.txt`, `run-log.jsonl`)

## Input

| Parameter | Required | Default | Description |
|---|---|---|---|
| `project` | **Yes** | — | Project name (human-readable, used in reports) |
| `branch` | No | Current branch | Branch to close out |
| `base` | No | `origin/main` | Base ref for comparison |
| `output-dir` | No | `.ralph/closeout/` | Output directory for closeout artifacts |
| `prd` | No | — | Path to `prd.json` for Linear issue status in checklist |
| `dry-run` | No | `false` | Show what would be done without executing |

## Output

All artifacts are written to `{output-dir}/{project-slug}/`:

| Artifact | File | Format |
|---|---|---|
| Branch divergence report | `divergence-report.json` | JSON |
| Artifact triage | `artifact-triage.json` | JSON |
| Coherence review | `coherence-review.json` | JSON |
| Release notes | `release-notes.md` | Markdown |
| Release notes (structured) | `release-notes.json` | JSON |
| Squash plan | `squash-plan.json` | JSON |
| Linear checklist | `linear-checklist.md` | Markdown |
| Linear checklist (structured) | `linear-checklist.json` | JSON |
| **Closeout summary** | `closeout-summary.json` | JSON |
| **Closeout report** | `closeout-summary.md` | Markdown |

The script also emits the summary JSON to stdout for tooling consumption.

## Process

### Stage 1: Inventory

Runs `scripts/branch-divergence-report.sh` to capture commit count, changed files, directory breakdown, and untracked files. Falls back to inline generation if the script is unavailable.

### Stage 2: Artifact Triage

Classifies every file (changed + untracked) into one of three categories:

| Category | Action | Examples |
|---|---|---|
| **Transient** | Delete from branch | `.ralph/results/`, `progress.txt`, `run-log.jsonl` |
| **Archival** | Attach to Linear, then delete | `run-log.jsonl`, retrospective JSON, review-queue |
| **Canonical** | Retain | Contracts, scripts, commands, templates, README |

### Stage 3: Coherence Review

Runs four sub-checks:
- **3a. Cross-reference integrity**: Finds markdown backtick references to non-existent files
- **3b. Orphan file check**: Identifies changed `.md` files not referenced anywhere
- **3c. README completeness**: Verifies `commands/README.md` lists all command files
- **3d. Contract-command parity**: Checks that contracts have matching command files

Emits a verdict (`pass` or `warnings`) with categorized issues.

### Stage 4: Release Summary

Generates human-readable release notes grouped by conventional commit type (`feat`, `fix`, `refactor`, `docs`, `chore`, `test`) plus a JSON sidecar with structured data.

### Stage 5: Squash Preparation

Runs `scripts/generate-squash-artifacts.js --phase pre` to analyze commits and emit a squash plan. Falls back to a minimal plan if the script is unavailable.

### Stage 6: Linear Transition Checklist

Generates a markdown checklist covering:
- Pre-merge verifications (issue status, artifact cleanup, coherence, release notes, squash)
- Artifact archival (attach to Linear before deletion)
- Project status updates (mark Completed, add final update, link PR)
- Post-merge cleanup (delete branch, verify CI, confirm Linear status)

If `--prd` is provided, includes issue status counts from the PRD.

## Example Invocation

```bash
# Full closeout with PRD awareness
scripts/project-closeout.sh \
  --project "Ralph Wiggum Flow" \
  --prd .cursor/ralph/ralph-wiggum-flow/prd.json

# Dry-run to preview stages
scripts/project-closeout.sh \
  --project "Ralph Wiggum Flow" \
  --dry-run

# Custom branch and output directory
scripts/project-closeout.sh \
  --project "My Feature" \
  --branch feature/my-feature \
  --base develop \
  --output-dir .closeout-artifacts/
```

## Cursor Command Usage

```
/project-closeout/run-closeout project="Ralph Wiggum Flow"
/project-closeout/run-closeout project="Ralph Wiggum Flow" --dry-run
/project-closeout/run-closeout project="My Feature" prd=".cursor/ralph/my-feature/prd.json"
```

## Related

- `commands/project-closeout/closeout-workflow.md` — Canonical 6-stage closeout workflow definition
- `scripts/branch-divergence-report.sh` — Stage 1 building block
- `scripts/generate-squash-artifacts.js` — Stage 5 building block
- `scripts/generate-retrospective.sh` — Retrospective generation for archival
- `commands/git/squash.md` — Full squash workflow for Stage 5 execution
- `templates/project-closeout/closeout-checklist.md` — Closeout checklist template
