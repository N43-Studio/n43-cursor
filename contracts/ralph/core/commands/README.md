# Command Contract Specs

This directory contains per-command source-of-truth contracts.

## Rule

- Command specs define command-level preconditions, postconditions, and contract outputs.
- Workflow sequencing and invariants stay centralized in `../linear-workflow.md`.
- Every command spec must link to the workflow invariants it must satisfy.
- Includes both bulk (`populate-project`) and single-item (`create-issue`) issue generation contracts.
- Issue-generation commands consume the shared metadata rubric in `../issue-metadata-rubric.md`.

## Required Command Contracts

| Command | Contract File | Primary Workflow Phase |
| --- | --- | --- |
| `build` | `build.md` | 1-4 (composite wrapper) |
| `create-project` | `create-project.md` | 1 |
| `populate-project` | `populate-project.md` | 2 |
| `generate-prd-from-project` | `generate-prd-from-project.md` | 3 |
| `audit-project` | `audit-project.md` | 4 |
| `ralph-run` | `ralph-run.md` | 5 |
