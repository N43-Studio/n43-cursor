#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# check-structural-readiness.sh
#
# Standalone structural readiness checker for Ralph PRD issues.
# Evaluates the 7 structural readiness checks defined in
# contracts/ralph/core/readiness-taxonomy.md and produces a per-issue
# report with pass/fail per check and overall readiness.
#
# Exit 0 when every evaluated issue is structurally ready.
# Exit 1 when at least one issue fails structural readiness.
# Exit 2 on usage / input errors.
#
# Usage:
#   check-structural-readiness.sh <prd.json>                    # all issues
#   check-structural-readiness.sh --issue '<json-object>'       # single issue
#   check-structural-readiness.sh <prd.json> --format json      # JSON output
#   check-structural-readiness.sh <prd.json> --format text      # human text
#   echo '<json>' | check-structural-readiness.sh --stdin        # pipe input
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT="text"
INPUT_MODE=""
INPUT_VALUE=""

usage() {
  cat <<'USAGE'
Usage:
  check-structural-readiness.sh <prd.json> [--format text|json]
  check-structural-readiness.sh --issue '<issue-json>' [--format text|json]
  check-structural-readiness.sh --stdin [--format text|json]

Options:
  --format text|json   Output format (default: text)
  --issue '<json>'     Evaluate a single issue JSON object
  --stdin              Read JSON from stdin (PRD or single issue)
  -h, --help           Show this help
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="${2:-text}"
      shift 2
      ;;
    --issue)
      INPUT_MODE="issue"
      INPUT_VALUE="${2:-}"
      [[ -z "$INPUT_VALUE" ]] && { echo "Error: --issue requires a JSON argument" >&2; exit 2; }
      shift 2
      ;;
    --stdin)
      INPUT_MODE="stdin"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: unknown option $1" >&2
      usage
      ;;
    *)
      if [[ -z "$INPUT_MODE" ]]; then
        INPUT_MODE="file"
        INPUT_VALUE="$1"
      fi
      shift
      ;;
  esac
done

[[ -z "$INPUT_MODE" ]] && { echo "Error: no input provided" >&2; usage; }

get_input_json() {
  case "$INPUT_MODE" in
    file)
      [[ ! -f "$INPUT_VALUE" ]] && { echo "Error: file not found: $INPUT_VALUE" >&2; exit 2; }
      cat "$INPUT_VALUE"
      ;;
    issue)
      echo "$INPUT_VALUE"
      ;;
    stdin)
      cat
      ;;
  esac
}

# Normalise input: if it looks like a single issue (has issueId but no .issues),
# wrap it into a PRD-shaped envelope so the jq below always iterates .issues[].
normalise_input() {
  jq -c '
    if (.issues | type) == "array" then .
    elif (.issueId // null) != null then { issues: [.] }
    elif type == "array" then { issues: . }
    else error("Unrecognised input shape: expected PRD, issue, or array of issues")
    end
  '
}

# ---- Core jq: mirrors ralph-run.sh next_issue() structural checks exactly ---
READINESS_JQ='
def parse_description($candidate):
  if ($candidate.description | type) == "string" then $candidate.description
  elif ($candidate.description | type) == "object" and ($candidate.description.text | type) == "string" then $candidate.description.text
  else ($candidate.description // "") | tostring
  end;

def parse_labels($candidate):
  (
    if ($candidate.labels | type) == "array" then $candidate.labels
    elif ($candidate.linearLabels | type) == "array" then $candidate.linearLabels
    else [] end
  )
  | map(
      if type == "string" then .
      elif type == "object" then (.name // .label // .id // "") | tostring
      else tostring end
    )
  | map(select(length > 0));

.issues as $issues
| [
    $issues[] as $candidate
    | ($candidate.issueId // $candidate.id // "unknown") as $id
    | ($candidate.title // "") as $title
    | parse_description($candidate) as $description
    | parse_labels($candidate) as $labels
    | ($description | gsub("\\r"; "")) as $dn
    | ($dn | gsub("^\\s+|\\s+$"; "")) as $dt
    | (($dt | length) > 0) as $has_description
    | ($dt | test("(?im)^##\\s*(goal|context)\\b")) as $has_goal_or_context
    | ($dt | test("(?im)^##\\s*(scope|implementation notes|implementation plan|approach|non-goals|constraints)\\b")) as $has_scope_signal
    | ($dt | test("(?im)^##\\s*acceptance criteria\\b")) as $has_acceptance_heading
    | ($dt | test("(?m)^\\s*[-*]\\s*\\[[ xX]\\]\\s+")) as $has_acceptance_checklist
    | ($dt | test("(?im)^##\\s*validation\\b")) as $has_validation_heading
    | ($dt | test("(?im)^\\s*[-*]\\s*`?(lint|typecheck|test|build)`?\\s*[:\\-]")) as $has_validation_checks
    | ($dt | test("(?im)^##\\s*metadata rationale\\b")) as $has_metadata_section
    | (($dt | test("(?im)\\bpriority\\b\\s*[:=]")) and ($dt | test("(?im)\\bestimate(dpoints)?\\b\\s*[:=]"))) as $has_metadata_values
    | (($labels | index("Human Required")) != null) as $has_human_required
    | (($labels | index("Ralph")) != null) as $has_ralph
    | (($labels | index("PRD Ready")) != null) as $has_prd_ready
    | ($has_description and $has_goal_or_context and $has_scope_signal and ($has_acceptance_heading or $has_acceptance_checklist) and ($has_validation_heading or $has_validation_checks) and ($has_metadata_section or $has_metadata_values) and ($has_human_required | not)) as $structural_ready
    | ($has_ralph and $has_prd_ready and ($has_human_required | not)) as $label_migration_ready
    | ($structural_ready or $label_migration_ready) as $overall_ready
    | (
        if $structural_ready then "structural"
        elif $label_migration_ready then "label_migration"
        else "not_ready"
        end
      ) as $readiness_source
    | {
        issueId: $id,
        title: $title,
        ready: $overall_ready,
        readiness_source: $readiness_source,
        structural_ready: $structural_ready,
        label_migration_ready: $label_migration_ready,
        has_human_required: $has_human_required,
        checks: {
          has_description: $has_description,
          has_goal_or_context: $has_goal_or_context,
          has_scope_signal: $has_scope_signal,
          has_acceptance: ($has_acceptance_heading or $has_acceptance_checklist),
          has_validation: ($has_validation_heading or $has_validation_checks),
          has_metadata: ($has_metadata_section or $has_metadata_values),
          human_required_absent: ($has_human_required | not)
        },
        structural_signals: {
          has_description: $has_description,
          has_goal_or_context: $has_goal_or_context,
          has_scope_signal: $has_scope_signal,
          has_acceptance_heading: $has_acceptance_heading,
          has_acceptance_checklist: $has_acceptance_checklist,
          has_validation_heading: $has_validation_heading,
          has_validation_checks: $has_validation_checks,
          has_metadata_section: $has_metadata_section,
          has_metadata_values: $has_metadata_values
        },
        legacy_label_signals: {
          has_ralph: $has_ralph,
          has_prd_ready: $has_prd_ready
        }
      }
  ] as $results
| {
    summary: {
      total: ($results | length),
      structurally_ready: ([$results[] | select(.structural_ready)] | length),
      label_migration_only: ([$results[] | select(.label_migration_ready and (.structural_ready | not))] | length),
      not_ready: ([$results[] | select(.ready | not)] | length),
      all_ready: (([$results[] | select(.ready | not)] | length) == 0)
    },
    issues: $results
  }
'

REPORT_JSON=$(get_input_json | normalise_input | jq -c "$READINESS_JQ")

if [[ "$FORMAT" == "json" ]]; then
  echo "$REPORT_JSON" | jq .
else
  total=$(echo "$REPORT_JSON" | jq '.summary.total')
  struct_ready=$(echo "$REPORT_JSON" | jq '.summary.structurally_ready')
  label_only=$(echo "$REPORT_JSON" | jq '.summary.label_migration_only')
  not_ready=$(echo "$REPORT_JSON" | jq '.summary.not_ready')
  all_ready=$(echo "$REPORT_JSON" | jq -r '.summary.all_ready')

  echo "═══════════════════════════════════════════════════"
  echo " Structural Readiness Report"
  echo "═══════════════════════════════════════════════════"
  echo ""
  echo "Total issues:            $total"
  echo "Structurally ready:      $struct_ready"
  echo "Label migration only:    $label_only (deprecation warning)"
  echo "Not ready:               $not_ready"
  echo ""

  if [[ "$all_ready" == "true" ]]; then
    echo "✔ All issues are ready for automation."
  else
    echo "✘ Some issues are NOT ready for automation."
  fi
  echo ""

  echo "$REPORT_JSON" | jq -r '
    .issues[] |
    "───────────────────────────────────────────────────\n" +
    "Issue: \(.issueId)  \(.title)\n" +
    "  Readiness source: \(.readiness_source)\n" +
    "  Overall ready:    \(if .ready then "YES" else "NO" end)\n" +
    "  Checks:\n" +
    "    [" + (if .checks.has_description then "✔" else "✘" end) + "] Description non-empty\n" +
    "    [" + (if .checks.has_goal_or_context then "✔" else "✘" end) + "] Goal or Context heading\n" +
    "    [" + (if .checks.has_scope_signal then "✔" else "✘" end) + "] Scope or implementation-plan signal\n" +
    "    [" + (if .checks.has_acceptance then "✔" else "✘" end) + "] Acceptance criteria\n" +
    "    [" + (if .checks.has_validation then "✔" else "✘" end) + "] Validation expectations\n" +
    "    [" + (if .checks.has_metadata then "✔" else "✘" end) + "] Metadata rationale\n" +
    "    [" + (if .checks.human_required_absent then "✔" else "✘" end) + "] Human Required absent\n" +
    (if .readiness_source == "label_migration" then
      "  ⚠  DEPRECATION: Admitted via label migration fallback only.\n" +
      "     Missing structural signals — add the required headings to the issue description.\n"
    elif .readiness_source == "not_ready" then
      "  ✘  NOT READY: Fails both structural and label-migration readiness.\n"
    else "" end)
  '
  echo "═══════════════════════════════════════════════════"
fi

all_ready=$(echo "$REPORT_JSON" | jq -r '.summary.all_ready')
if [[ "$all_ready" == "true" ]]; then
  exit 0
else
  exit 1
fi
