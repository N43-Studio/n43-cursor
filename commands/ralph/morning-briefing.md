> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Deterministic synthesis from Ralph runtime artifacts into a morning developer briefing -->

# Morning Briefing

Generate a deterministic morning briefing from overnight Ralph runtime artifacts. Aggregates run-log, retrospective, progress, and PRD data into a single developer-facing markdown view with optional JSON sidecar.

## Input

`$ARGUMENTS` supports:

- `run_log=<path>` (required) — path to `run-log.jsonl`
- `retrospective=<path>` (optional) — path to `retrospective.json`
- `progress=<path>` (optional) — path to `progress.txt` for run-window scoping
- `prd=<path>` (optional) — path to `prd.json` for project-state section
- `output=<path>` (optional, default `.cursor/reviews/morning-briefing.md`)
- `json=<path>` (optional) — JSON sidecar output path
- `project_slug=<slug>` (optional) — derive default retrospective/prd paths from `.cursor/ralph/<slug>/`
- `run_id=<id>` (optional) — traceability identifier

Example:

```text
/ralph/morning-briefing \
  run_log="run-log.jsonl" \
  retrospective=".cursor/ralph/ralph-wiggum-flow/retrospective.json" \
  prd=".cursor/ralph/ralph-wiggum-flow/prd.json" \
  progress="progress.txt"
```

Shorthand with project slug:

```text
/ralph/morning-briefing \
  run_log="run-log.jsonl" \
  project_slug="ralph-wiggum-flow"
```

## Process

Invoke:

```bash
scripts/generate-morning-briefing.sh \
  --run-log "<run_log>" \
  --retrospective "<retrospective>" \
  --progress "<progress>" \
  --prd "<prd>" \
  --output "<output>" \
  --json "<json>" \
  --project-slug "<project_slug>" \
  --run-id "<run_id>"
```

Only `--run-log` and `--output` are required. All other inputs are optional and enrich the output when present.

## Output Sections

The markdown briefing contains six numbered sections:

1. **Overnight Summary** — run window, iterations executed, pass/fail counts, files changed, token usage
2. **Issue Outcomes** — per-issue table grouped by: completed, needs review, blocked/failed
3. **Decision Queue** — issues needing human input (human_required or failed), sorted by urgency with blocker reason
4. **Project State** — remaining PRD issues, estimated effort, dependency blockers (requires `--prd`)
5. **Risk Flags** — multiple retries, failed validations, execution incidents, retrospective warnings
6. **Recommended Actions** — prioritized list of next steps

The JSON sidecar (`--json`) contains machine-readable versions of all six sections for automation and downstream tooling.

## Safety

1. Only `--run-log` and `--output` are hard-required; all other inputs gracefully degrade.
2. Read-only — no Linear mutations, no file modifications outside the output paths.
3. Deterministic ordering throughout (timestamp-window filtering, priority sorting, alphabetical tiebreakers).
4. When `--project-slug` is given, default paths are only used if the derived files actually exist.
