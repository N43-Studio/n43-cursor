> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Deterministic synthesis from Ralph execution and review artifacts into a morning operator briefing -->

# Generate Morning Ralph Briefing

Generate a deterministic morning briefing package from overnight Ralph runtime artifacts and the Linear review queue export.

## Input

`$ARGUMENTS` supports:

- `run_log=<path>` (required)
- `retrospective=<path>` (required)
- `review_queue=<path>` (required)
- `progress=<path>` (optional)
- `output=<path>` (optional, default `.cursor/reviews/morning-ralph-briefing.md`)
- `sidecar=<path>` (optional, default `.cursor/reviews/morning-ralph-briefing.json`)
- `run_id=<id>` (optional)

Example:

```text
/code-review/generate-morning-briefing \
  run_log="run-log.jsonl" \
  retrospective=".cursor/ralph/ralph-wiggum-flow/retrospective.json" \
  review_queue=".cursor/ralph/ralph-wiggum-flow/review-queue.json" \
  progress="progress.txt"
```

## Process

Invoke:

```bash
scripts/generate-morning-briefing.sh \
  --run-log "<run_log>" \
  --retrospective "<retrospective>" \
  --review-queue "<review_queue>" \
  --progress "<progress>" \
  --output "<output>" \
  --sidecar "<sidecar>" \
  --run-id "<run_id>"
```

The generator performs deterministic ordering and emits both outputs in one pass.

## Output

- Markdown briefing sections:
  - `Inputs and Traceability`
  - `Overnight Summary`
  - `Decision Queue`
  - `Project State`
- JSON sidecar with normalized fields for automation and post-processing.

## Safety

1. Treat missing `run_log`, `retrospective`, or `review_queue` as hard errors.
2. Keep this slice read-only; no Linear mutations are performed.
3. Preserve deterministic ordering (priority -> updated time -> issue id) for decision queue output.
