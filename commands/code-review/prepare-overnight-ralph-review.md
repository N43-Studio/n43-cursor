> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Structured synthesis from Ralph run artifacts into a deterministic review package -->

# Prepare Overnight Ralph Review

Generate a high-signal overnight review playbook from Ralph run artifacts so morning triage starts with one deterministic context document.

## Input

`$ARGUMENTS` supports:

- `run_log=<path>` (default: `run-log.jsonl`)
- `progress=<path>` (default: `progress.txt`)
- `results_dir=<path>` (default: `.ralph/results`)
- `output=<path>` (default: `.cursor/reviews/overnight-ralph-review-context.md`)

## Templates

Use these reusable templates:

- `templates/code-review/overnight-ralph-review-context.md`
- `templates/code-review/overnight-ralph-review-checklist.md`

If running from a consumer repo with this project as `.n43-cursor`, resolve the same files under `.n43-cursor/templates/code-review/`.

## Process

Invoke:

```bash
scripts/prepare-overnight-review.sh \
  --run-log "<run_log>" \
  --results-dir "<results_dir>" \
  --progress "<progress>" \
  --output "<output>" \
  --checklist "<output_dir>/overnight-ralph-review-checklist.md"
```

The script performs deterministic synthesis and emits both outputs in one pass.

### Steps

1. Validate that `run_log`, `progress`, and `results_dir` exist.
2. Parse the latest overnight execution window from `progress.txt` (`RUN_START` to `RUN_COMPLETE`).
3. Build an issue ledger from `run-log.jsonl` and matching `*-result.json` files:
   - issue id/title
   - outcome, failure category, retryability
   - summary
   - validation results
   - artifact file path
4. Aggregate changed areas from `artifacts.files_changed` (group by top-level and second-level path prefixes).
5. Generate the review context markdown using `overnight-ralph-review-context.md`, including:
   - links/paths to `progress.txt`, `run-log.jsonl`, and per-issue result JSON
   - issues requiring triage first (`failure`, `human_required`, then risky `success`)
   - changed-area heatmap
   - validation signal summary
6. Append `overnight-ralph-review-checklist.md` into the output so reviewers have one complete playbook.

## Severity Sorting

Sort issue triage order as:

1. Security/regression/data-loss risk
2. `outcome=human_required`
3. `outcome=failure`
4. `outcome=success` with partial/skipped validations
5. Remaining successful issues

## Completion Response

Return:

1. Output document path
2. Issue counts by outcome
3. Top changed areas
4. First-pass triage queue (ordered)
