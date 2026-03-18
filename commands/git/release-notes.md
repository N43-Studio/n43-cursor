> **Recommended Model**: Tier 2 - Claude 4.5 Sonnet

<!-- **Why**: Deterministic synthesis over git history with structured sidecar output -->

# Generate Release Notes

Create high-signal release notes for a git range using the canonical script surface.

## Input

`$ARGUMENTS` supports:

- `since=<commit-or-tag>` (required)
- `until=<commit-or-tag>` (optional, default `HEAD`)
- `scope=<path>` (optional, repeatable)
- `output=<markdown-path>` (optional)
- `sidecar=<json-path>` (optional)

Example:

```text
/git/release-notes since=v0.3.0 until=HEAD output=.ralph/release-notes.md sidecar=.ralph/release-notes.json
```

## Process

Invoke:

```bash
node scripts/generate-release-notes.js \
  --since "<since>" \
  --until "<until>" \
  --output "<output>" \
  --sidecar "<sidecar>"
```

Add one `--scope "<path>"` flag per provided scope filter.

## Output

- Human-readable markdown:
  - `Summary`
  - `Source Range`
  - `Top Changes`
  - optional `Critical Additions`
  - `Also Changed`
- Machine-readable JSON sidecar with grouped traceability back to commits/files/issues

## Safety

1. Fail fast on invalid refs.
2. Never rewrite history.
3. Prefer explicit `since` references; do not guess the range.
