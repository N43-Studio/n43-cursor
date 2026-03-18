# Project Closeout Checklist

> **Project**: _<project name>_
> **Branch**: _<branch name>_
> **Date**: _<YYYY-MM-DD>_
> **Operator**: _<name or agent>_

Reference: `commands/project-closeout/closeout-workflow.md`

---

## Stage 1: Inventory

- [ ] Run branch divergence report
- [ ] Record commit count: ___
- [ ] Record files changed: ___
- [ ] Record untracked files count: ___
- [ ] Note any unexpected files or directories

**Observations**: _<notes on branch scope>_

---

## Stage 2: Artifact Triage

### Transient (delete from branch)

- [ ] `.ralph/results/` — per-issue iteration results
- [ ] `.ralph/results-*/` — retry result directories
- [ ] `.ralph/squash-artifacts/` — squash plan/mapping JSONs
- [ ] `progress.txt` — loop progress tracker
- [ ] `run-log.jsonl` — runtime execution log
- [ ] `assumptions-log.jsonl` — assumption tracking (if present)
- [ ] Other: ___

### Archival (attach to Linear, then delete)

- [ ] Retrospective JSON attached to Linear project
- [ ] Run-log summary attached to Linear project
- [ ] Review-queue decisions attached to Linear project
- [ ] Other: ___

### Canonical (verify retained)

- [ ] Contracts are present and complete
- [ ] Commands are present and complete
- [ ] Scripts are present and executable
- [ ] Templates are present
- [ ] README updates reflect current state
- [ ] Skills are present (if applicable)

### Cleanup Commit

- [ ] All transient files removed
- [ ] Cleanup committed as `chore: remove transient Ralph runtime artifacts`

---

## Stage 3: Coherence Review

### Cross-References

- [ ] No broken file references in contracts
- [ ] No broken file references in commands
- [ ] No broken file references in READMEs

### Orphan Check

- [ ] No orphan files (files not referenced by any index or cross-reference)
- [ ] All new files are listed in their parent README or index

### README Completeness

- [ ] `commands/README.md` lists all commands
- [ ] `contracts/ralph/core/commands/README.md` lists all command contracts
- [ ] Other index files are up-to-date

### Contract-Command Parity

- [ ] Each command has a corresponding contract (where applicable)
- [ ] Each contract has a corresponding command (where applicable)

**Issues found**: _<list any issues and their resolutions>_

---

## Stage 4: Release Summary

- [ ] Release notes generated (markdown)
- [ ] Release notes cover all change types (feat, fix, refactor, docs, chore, test)
- [ ] Release notes include Linear issue references
- [ ] Release notes saved to: ___

---

## Stage 5: Squash/Merge Preparation

- [ ] Working directory is clean before squash
- [ ] Commit grouping analysis completed
- [ ] Squash strategy selected: _<single / grouped / split>_
- [ ] Squash plan artifact generated
- [ ] Squash branch created: ___
- [ ] Squash executed
- [ ] `git diff <source> <squash>` is empty (tree equivalence verified)
- [ ] Post-squash artifacts generated
- [ ] Squash branch pushed to origin

---

## Stage 6: Linear Project Transition

### Issue Status

- [ ] All PRD issues verified as `Done` or `Cancelled`
- [ ] Remaining non-terminal issues investigated and resolved
- [ ] Issue count — Done: ___ / Cancelled: ___ / Other: ___

### Artifacts Attached

- [ ] Release notes attached to Linear project
- [ ] Retrospective attached to Linear project
- [ ] Run-log summary attached to Linear project
- [ ] Squash verification attached to Linear project

### Project Status

- [ ] Linear project status set to `Completed`
- [ ] Final project update written
- [ ] PR linked to project and relevant issues

---

## Final Verification

- [ ] No transient artifacts remain in branch
- [ ] All cross-references are valid
- [ ] Release notes exist and are accurate
- [ ] Squash branch is tree-equivalent to source branch
- [ ] Linear project reflects completed state
- [ ] PR is self-explanatory for an outside reviewer

**Sign-off**: _<name/agent>_ — _<date>_
