# Token Usage Capture Contract

This contract documents the end-to-end token usage telemetry flow through the Ralph execution pipeline, from agent execution to calibration store.

## Pipeline Stages

```
Agent Backend  →  Execution Result  →  Run-Log  →  Retrospective  →  Calibration Store
(codex/cursor)    (token_usage)        (JSONL)     (aggregates)       (tokensPerPoint)
```

### 1. Agent Backend → Execution Result

The CLI issue agent (e.g. `scripts/codex-issue-agent.sh`) writes the execution result with structured token usage:

```json
{
  "metrics": {
    "duration_ms": 45000,
    "tokens_used": 8421,
    "token_usage": {
      "input_tokens": 5200,
      "output_tokens": 3221,
      "total_tokens": 8421,
      "source": "codex_api"
    }
  }
}
```

Token extraction from codex:
- `scripts/extract-codex-token-usage.sh --events <path> --structured` parses the codex `--json` event stream
- Extracts `input_tokens`, `output_tokens`, `total_tokens` from usage objects in events
- Sets `source: "codex_api"` when real telemetry is found
- Falls back to `source: "unavailable"` with zero values when no telemetry exists

The agent injects telemetry into the result only when the codex-written result lacks it.

### 2. Execution Result → Run-Log

`scripts/ralph-run.sh` extracts `token_usage` from the execution result and writes it to the run-log JSONL sidecar:

```json
{
  "tokensUsed": 8421,
  "tokenTelemetryAvailable": true,
  "tokenUsage": {
    "input_tokens": 5200,
    "output_tokens": 3221,
    "total_tokens": 8421,
    "source": "codex_api"
  }
}
```

The `tokensUsed` scalar is preserved for backward compatibility. `tokenUsage` is the structured replacement. When `tokenUsage.source` is not `"unavailable"`, `tokenTelemetryAvailable` is `true`.

Stage telemetry accumulates `input_tokens_used`, `output_tokens_used`, `telemetry_reported_count`, and `telemetry_unavailable_count`.

### 3. Run-Log → Retrospective

`scripts/generate-retrospective.sh` reads run-log entries and computes per-issue aggregates:

- `actualTokens`: total tokens across reported attempts
- `actualInputTokens`: total input tokens across reported attempts
- `actualOutputTokens`: total output tokens across reported attempts
- `tokenSources`: unique set of sources across all attempts
- `tokenTelemetryStatus`: `"reported"`, `"partial"`, or `"missing"`
- `inputOutputRatio`: ratio of input to output tokens
- `tokensPerEstimatedPoint`: tokens per estimated story point (when both are available)

The retrospective also includes a `tokenUsageAggregate` section with run-level totals.

### 4. Retrospective → Calibration Store

`scripts/update-calibration-store.sh` merges retrospective data into the calibration store:

- Samples with `hasRealTelemetry: true` (source is `codex_api` or `cursor_api`) are weighted 2x
- Samples with only estimated or legacy scalar telemetry receive standard 1x weight
- When no usable samples exist, the baseline fallback (`3200` tokens/point) is preserved
- `realTelemetrySampleCount` and `estimatedTelemetrySampleCount` track sample provenance

## Source Priority

| Priority | Source | Description |
|----------|--------|-------------|
| 1 (highest) | `codex_api` | Direct extraction from codex CLI event stream |
| 2 | `cursor_api` | Extracted from Cursor runtime telemetry |
| 3 | `estimated` | Heuristic estimate, not from direct measurement |
| 4 (lowest) | `unavailable` | No telemetry data; all counts are zero |

## Backward Compatibility

- `metrics.tokens_used` (integer\|null) remains the primary scalar field and is always written
- `metrics.token_usage` (object\|null) is optional; older results without it are treated as `source: "unavailable"`
- Run-log entries without `tokenUsage` are handled via the existing `tokensUsed`/`tokenTelemetryAvailable` fallback
- Calibration samples without `hasRealTelemetry` default to `false` (standard weight)
- The `calibrationVersion` field in `calibration.json` tracks schema evolution

## Fallback Behavior

When `token_usage` is null or `source` is `"unavailable"`:
- `ralph-run.sh` sets `tokenTelemetryAvailable: false` and `tokensUsed: null`
- Retrospective marks the issue as `tokenTelemetryStatus: "missing"`
- Calibration store treats the sample as non-usable (`calibrationUsable: false`)
- The baseline `tokensPerPoint` fallback (3200) is preserved when no usable samples exist
