# Overnight Ralph Review Context

## Run Artifacts

- Branch: `<branch>`
- Workflow mode: `<workflow_mode>`
- Progress log: `<progress_path>`
- Run log: `<run_log_path>`
- Result directory: `<results_dir>`
- Generated at: `<generated_at_iso8601>`

## Outcome Snapshot

| Metric | Value |
| --- | --- |
| Issues attempted | `<issues_attempted>` |
| Success | `<success_count>` |
| Failure | `<failure_count>` |
| Human required | `<human_required_count>` |
| Retryable failures | `<retryable_failure_count>` |

## First-Pass Triage Queue

Review this queue in order.

### 1. `<issue_id>` - `<issue_title>`

- Outcome: `<outcome>`
- Failure category: `<failure_category_or_none>`
- Retryable: `<retryable>`
- Summary: `<summary>`
- Result artifact: `<result_json_path>`
- Run-log timestamp: `<run_log_timestamp>`
- Changed areas:
  - `<changed_area_1>`
  - `<changed_area_2>`
- Changed files:
  - `<file_path_1>`
  - `<file_path_2>`

## Validation Signals

| Issue | lint | typecheck | test | build |
| --- | --- | --- | --- | --- |
| `<issue_id>` | `<lint_status>` | `<typecheck_status>` | `<test_status>` | `<build_status>` |

## Changed Area Heatmap

| Area Prefix | Issues Touched | Files Changed |
| --- | --- | --- |
| `<area_prefix_1>` | `<issues_touched_1>` | `<files_changed_1>` |
| `<area_prefix_2>` | `<issues_touched_2>` | `<files_changed_2>` |

## Notes For Morning Reviewer

- Start with failures/handoffs before successful issues.
- Confirm rollback options for any risky file groups.
- Record follow-up issue IDs for anything deferred.
