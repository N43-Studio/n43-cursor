# Command Contract Specs

This directory contains per-command source-of-truth contracts.

## Rule

- Command specs define command-level preconditions, postconditions, and contract outputs.
- Workflow sequencing and invariants stay centralized in `../linear-workflow.md`.
- Every command spec must link to the workflow invariants it must satisfy.
- Includes both bulk (`populate-project`) and single-item (`create-issue`) issue generation contracts.
