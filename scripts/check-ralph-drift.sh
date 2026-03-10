#!/usr/bin/env bash
#
# Guardrail checks for Ralph workflow drift across contracts and surfaces.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAPPING_FILE="contracts/ralph/adapters/mapping.md"
CURSOR_ADAPTER_FILE="contracts/ralph/adapters/cursor/README.md"
CODEX_ADAPTER_FILE="contracts/ralph/adapters/codex/README.md"
CODEX_SKILL_BOUNDARY_FILE="contracts/ralph/adapters/codex/skill-boundary.md"
NO_DRIFT_RULES_FILE="contracts/ralph/adapters/no-drift-rules.md"
ADAPTER_SMOKE_RUN_FILE="contracts/ralph/adapters/smoke-run.md"
SHARED_VALIDATIONS_FILE="contracts/ralph/core/shared-validations.md"
SCHEMA_FILE="contracts/ralph/core/schema/normalized-result.schema.json"
STATUS_SEMANTICS_FILE="contracts/ralph/core/status-semantics.md"
ISSUE_METADATA_RUBRIC_FILE="contracts/ralph/core/issue-metadata-rubric.md"
CLI_CONTRACT_FILE="contracts/ralph/core/cli-issue-execution-contract.md"
ISSUE_CREATION_CONTRACT_FILE="contracts/ralph/core/issue-creation-delegation-contract.md"
REVIEW_FEEDBACK_CONTRACT_FILE="contracts/ralph/core/review-feedback-sweep-contract.md"
RETROSPECTIVE_CONTRACT_FILE="contracts/ralph/core/retrospective-contract.md"
PLAN_MODE_CONTRACT_FILE="contracts/ralph/core/plan-mode-contract.md"
PLAN_MODE_SMOKE_FILE="contracts/ralph/adapters/plan-mode-smoke-run.md"
CLI_RESULT_SCHEMA_FILE="contracts/ralph/core/schema/cli-issue-execution-result.schema.json"
RALPH_RUN_SCRIPT="scripts/ralph-run.sh"
ISSUE_INTENT_ENQUEUE_SCRIPT="scripts/issue-intent-enqueue.sh"
ISSUE_INTENT_WORKER_SCRIPT="scripts/issue-intent-worker.sh"
REVIEW_FEEDBACK_SWEEP_SCRIPT="scripts/review-feedback-sweep.sh"
RETROSPECTIVE_SCRIPT="scripts/generate-retrospective.sh"
RETROSPECTIVE_IMPROVEMENT_SCRIPT="scripts/retrospective-to-issue-intents.sh"
BOOTSTRAP_SURFACES_SCRIPT="scripts/bootstrap-ralph-surfaces.sh"
METADATA_SCORER_SCRIPT="scripts/score-issue-metadata.sh"
RUN_LOG_TEMPLATE_FILE="templates/ralph-run-log-entry.example.json"

FAILURES=0

fail() {
  echo "FAIL $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS $1"
}

require_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    fail "missing file: $file"
    return 1
  fi
  pass "file exists: $file"
  return 0
}

extract_mapping_rows() {
  awk -F'|' '
    /^\| `[^`]+` \| `[^`]+` \| `[^`]+` \| `[^`]+` \|$/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/`/, "", $2); cmd=$2;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/`/, "", $3); cursor=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); gsub(/`/, "", $4); codex=$4;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); gsub(/`/, "", $5); core=$5;
      print cmd "|" cursor "|" codex "|" core;
    }
  ' "$MAPPING_FILE"
}

check_command_parity() {
  echo "== Check: Command Parity =="
  local rows
  rows="$(extract_mapping_rows || true)"
  if [ -z "$rows" ]; then
    fail "no mapping rows found in $MAPPING_FILE"
    return
  fi

  local count=0
  while IFS='|' read -r cmd cursor codex core_ref; do
    [ -z "$cmd" ] && continue
    count=$((count + 1))

    local expected_core="../../core/commands/${cmd}.md"
    if [ "$core_ref" != "$expected_core" ]; then
      fail "mapping core reference mismatch for ${cmd}: got ${core_ref}, expected ${expected_core}"
    else
      pass "mapping core reference aligned for ${cmd}"
    fi

    local core_file="contracts/ralph/core/commands/${cmd}.md"
    if [ ! -f "$core_file" ]; then
      fail "missing core command contract for ${cmd}: ${core_file}"
    else
      pass "core command contract exists for ${cmd}"
    fi

    if rg -n --fixed-strings "| \`${cmd}\` | \`${cursor}\` |" "$CURSOR_ADAPTER_FILE" >/dev/null; then
      pass "cursor mapping row present for ${cmd}"
    else
      fail "cursor mapping row missing for ${cmd}; expected '| \`${cmd}\` | \`${cursor}\` |' in ${CURSOR_ADAPTER_FILE}"
    fi

    if rg -n --fixed-strings "| \`${cmd}\` | \`${codex}\` |" "$CODEX_ADAPTER_FILE" >/dev/null; then
      pass "codex mapping row present for ${cmd}"
    else
      fail "codex mapping row missing for ${cmd}; expected '| \`${cmd}\` | \`${codex}\` |' in ${CODEX_ADAPTER_FILE}"
    fi

    local skill_file="skills/${codex}/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      fail "missing Codex wrapper skill for ${cmd}: ${skill_file}"
      continue
    fi
    pass "Codex wrapper skill exists for ${cmd}"

    if rg -n --fixed-strings "contracts/ralph/core/commands/${cmd}.md" "$skill_file" >/dev/null; then
      pass "skill wired to command contract for ${cmd}"
    else
      fail "skill missing command contract reference for ${cmd}: ${skill_file}"
    fi

    if rg -n --fixed-strings "contracts/ralph/core/shared-validations.md" "$skill_file" >/dev/null; then
      pass "skill wired to shared validations for ${cmd}"
    else
      fail "skill missing shared validations reference for ${cmd}: ${skill_file}"
    fi

    if rg -n --fixed-strings "contracts/ralph/adapters/mapping.md" "$skill_file" >/dev/null; then
      pass "skill wired to mapping contract for ${cmd}"
    else
      fail "skill missing mapping contract reference for ${cmd}: ${skill_file}"
    fi
  done <<< "$rows"

  if [ "$count" -eq 0 ]; then
    fail "mapping table parsed with zero command rows"
  else
    pass "parsed ${count} mapping rows"
  fi
}

check_schema_parity_and_freshness() {
  echo "== Check: Schema Parity And Freshness Hash =="
  require_file "$SCHEMA_FILE" || true
  require_file "$SHARED_VALIDATIONS_FILE" || true

  local schema_fields=(
    "\"issue_id\""
    "\"command_contract\""
    "\"status\""
    "\"validation_results\""
    "\"schema_freshness_hash\""
    "\"mapping_freshness_hash\""
  )
  local field
  for field in "${schema_fields[@]}"; do
    if rg -n --fixed-strings "$field" "$SCHEMA_FILE" >/dev/null; then
      pass "schema includes field ${field}"
    else
      fail "schema missing field ${field} in ${SCHEMA_FILE}"
    fi
  done

  if rg -n --fixed-strings "schema_freshness_hash" "$SHARED_VALIDATIONS_FILE" >/dev/null \
    && rg -n --fixed-strings "mapping_freshness_hash" "$SHARED_VALIDATIONS_FILE" >/dev/null; then
    pass "shared validations require freshness hash fields"
  else
    fail "shared validations missing freshness hash fields in ${SHARED_VALIDATIONS_FILE}"
  fi

  if rg -n --fixed-strings "../../core/schema/normalized-result.schema.json" "$CURSOR_ADAPTER_FILE" >/dev/null \
    && rg -n --fixed-strings "../../core/schema/normalized-result.schema.json" "$CODEX_ADAPTER_FILE" >/dev/null; then
    pass "Cursor/Codex adapters reference same canonical schema"
  else
    fail "schema parity drift: adapters must both reference ../../core/schema/normalized-result.schema.json"
  fi
}

check_plan_mode_parity() {
  echo "== Check: Plan Mode Parity Contract =="
  require_file "$PLAN_MODE_CONTRACT_FILE" || true
  require_file "$PLAN_MODE_SMOKE_FILE" || true

  if rg -n --fixed-strings "plan-mode-contract.md" "$CURSOR_ADAPTER_FILE" >/dev/null; then
    pass "cursor adapter references plan-mode parity contract"
  else
    fail "cursor adapter missing plan-mode parity contract reference"
  fi

  if rg -n --fixed-strings "plan-mode-contract.md" "$CODEX_ADAPTER_FILE" >/dev/null; then
    pass "codex adapter references plan-mode parity contract"
  else
    fail "codex adapter missing plan-mode parity contract reference"
  fi

  if rg -n --fixed-strings "commands/implementation/plan-feature.md" "rules/orchestrator.mdc" >/dev/null \
    && rg -n --fixed-strings "plan-mode-contract.md" "rules/orchestrator.mdc" >/dev/null; then
    pass "orchestrator rule enforces plan-feature parity routing"
  else
    fail "orchestrator rule missing explicit plan-feature parity routing references"
  fi

  if rg -n --fixed-strings "plan-mode-contract.md" "commands/implementation/implement.md" >/dev/null \
    && rg -n --fixed-strings "plan-mode-contract.md" "commands/implementation/plan-feature.md" >/dev/null; then
    pass "implementation commands reference shared plan-mode contract"
  else
    fail "implementation commands missing shared plan-mode contract references"
  fi

  if rg -n --fixed-strings "plan-feature" "$PLAN_MODE_SMOKE_FILE" >/dev/null \
    && rg -n --fixed-strings "approval" "$PLAN_MODE_SMOKE_FILE" >/dev/null; then
    pass "plan-mode smoke run documents parity + approval checks"
  else
    fail "plan-mode smoke run missing parity or approval verification steps"
  fi
}

check_adapter_no_drift_rules() {
  echo "== Check: Adapter No-Drift Rules =="
  require_file "$NO_DRIFT_RULES_FILE" || true

  if rg -n --fixed-strings "no-drift-rules.md" "$CURSOR_ADAPTER_FILE" >/dev/null \
    && rg -n --fixed-strings "no-drift-rules.md" "$CODEX_ADAPTER_FILE" >/dev/null; then
    pass "cursor/codex adapters reference no-drift rules contract"
  else
    fail "cursor/codex adapters must both reference no-drift-rules.md"
  fi

  if rg -n --fixed-strings "One-to-One Mapping Rule" "$NO_DRIFT_RULES_FILE" >/dev/null \
    && rg -n --fixed-strings "Prohibited Divergence Examples" "$NO_DRIFT_RULES_FILE" >/dev/null; then
    pass "no-drift rules include mapping rule and prohibited divergence examples"
  else
    fail "no-drift rules contract missing required sections"
  fi
}

check_dual_surface_bootstrap_contract() {
  echo "== Check: Dual-Surface Bootstrap =="
  require_file "$BOOTSTRAP_SURFACES_SCRIPT" || true

  if rg -n --fixed-strings "install" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "verify" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null; then
    pass "bootstrap script supports install and verify modes"
  else
    fail "bootstrap script missing install/verify mode support"
  fi

  if rg -n --fixed-strings "RESULT_SUMMARY" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "RESULT PASS" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "RESULT FAIL" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null; then
    pass "bootstrap script emits deterministic summary/result markers"
  else
    fail "bootstrap script missing deterministic summary/result markers"
  fi

  if rg -n --fixed-strings "agents commands references rules skills" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "ralph-create-project" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "ralph-run" "$BOOTSTRAP_SURFACES_SCRIPT" >/dev/null; then
    pass "bootstrap script covers required Cursor and Codex link targets"
  else
    fail "bootstrap script missing required Cursor/Codex link targets"
  fi
}

check_cli_issue_contract() {
  echo "== Check: CLI Issue Execution Contract =="
  require_file "$CLI_CONTRACT_FILE" || true
  require_file "$CLI_RESULT_SCHEMA_FILE" || true
  require_file "$RALPH_RUN_SCRIPT" || true

  if rg -n --fixed-strings "cli-issue-execution-contract.md" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run command contract references CLI issue contract"
  else
    fail "ralph-run command contract missing CLI issue contract reference"
  fi

  if rg -n --fixed-strings "cli-issue-execution-result.schema.json" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run command contract references CLI result schema"
  else
    fail "ralph-run command contract missing CLI result schema reference"
  fi

  if rg -n --fixed-strings "Run-Level Resume Semantics" "$CLI_CONTRACT_FILE" >/dev/null; then
    pass "CLI contract documents resume semantics"
  else
    fail "CLI contract missing resume semantics section"
  fi

  if rg -n --fixed-strings "Canonical vs Sidecar Artifacts" "$CLI_CONTRACT_FILE" >/dev/null; then
    pass "CLI contract documents canonical vs sidecar artifacts"
  else
    fail "CLI contract missing canonical vs sidecar artifact section"
  fi

  if rg -n --fixed-strings -- "--resume" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "loop-state" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script exposes resume + loop-state options"
  else
    fail "ralph-run script missing resume/loop-state runtime options"
  fi

  if rg -n --fixed-strings "RUN_START" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "RUN_ITERATION" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "RUN_COMPLETE" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script writes canonical progress markers"
  else
    fail "ralph-run script missing canonical progress markers"
  fi
}

check_issue_creation_delegation_contract() {
  echo "== Check: Issue Creation Delegation Contract =="
  require_file "$ISSUE_CREATION_CONTRACT_FILE" || true
  require_file "$ISSUE_INTENT_ENQUEUE_SCRIPT" || true
  require_file "$ISSUE_INTENT_WORKER_SCRIPT" || true

  if rg -n --fixed-strings "issue-creation-delegation-contract.md" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run contract references issue-creation delegation contract"
  else
    fail "ralph-run contract missing issue-creation delegation contract reference"
  fi

  if rg -n --fixed-strings -- "--issue-intent-queue" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--issue-intent-results" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--process-issue-intents" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script exposes delegated issue-intent options"
  else
    fail "ralph-run script missing delegated issue-intent options"
  fi
}

check_review_feedback_sweep_contract() {
  echo "== Check: Review Feedback Sweep Contract =="
  require_file "$REVIEW_FEEDBACK_CONTRACT_FILE" || true
  require_file "$REVIEW_FEEDBACK_SWEEP_SCRIPT" || true

  if rg -n --fixed-strings "review-feedback-sweep-contract.md" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run contract references review-feedback sweep contract"
  else
    fail "ralph-run contract missing review-feedback sweep contract reference"
  fi

  if rg -n --fixed-strings -- "--process-review-feedback-sweep" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--review-feedback-sweep-cmd" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--review-feedback-events" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script exposes review-feedback sweep options"
  else
    fail "ralph-run script missing review-feedback sweep options"
  fi
}

check_retrospective_contract() {
  echo "== Check: Retrospective Contract =="
  require_file "$RETROSPECTIVE_CONTRACT_FILE" || true
  require_file "$RETROSPECTIVE_SCRIPT" || true
  require_file "$RETROSPECTIVE_IMPROVEMENT_SCRIPT" || true

  if rg -n --fixed-strings "retrospective-contract.md" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run contract references retrospective contract"
  else
    fail "ralph-run contract missing retrospective contract reference"
  fi

  if rg -n --fixed-strings -- "--process-retrospective" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--retrospective-cmd" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--retrospective" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script exposes retrospective options"
  else
    fail "ralph-run script missing retrospective options"
  fi

  if rg -n --fixed-strings -- "--process-retrospective-improvements" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings -- "--retrospective-improvement-cmd" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script exposes retrospective improvement pipeline options"
  else
    fail "ralph-run script missing retrospective improvement pipeline options"
  fi
}

check_terminal_runtime_boundary() {
  echo "== Check: Terminal Runtime Boundary =="
  local run_wrapper_file="commands/ralph/run.md"
  local run_contract_file="contracts/ralph/core/commands/ralph-run.md"
  local cli_contract_file="contracts/ralph/core/cli-issue-execution-contract.md"
  local deprecated_agent_file="agents/ralph-runner.md"

  require_file "$run_wrapper_file" || true
  require_file "$run_contract_file" || true
  require_file "$cli_contract_file" || true
  require_file "$deprecated_agent_file" || true

  local runtime_refs=(
    "$run_wrapper_file"
    "$run_contract_file"
    "$cli_contract_file"
  )
  local target=""
  for target in "${runtime_refs[@]}"; do
    if rg -n --fixed-strings "scripts/ralph-run.sh" "$target" >/dev/null; then
      pass "terminal runtime reference present in ${target}"
    else
      fail "missing terminal runtime reference in ${target}"
    fi
  done

  local forbidden_terms=(
    "scriptless"
    "subagent"
    "ralph-runner"
    "Task tool"
  )
  local term=""
  for term in "${forbidden_terms[@]}"; do
    if rg -n --fixed-strings "$term" "$run_wrapper_file" "$run_contract_file" "$cli_contract_file" >/dev/null; then
      fail "forbidden runtime term '${term}' present in Ralph runtime contracts/docs"
    else
      pass "forbidden runtime term absent: ${term}"
    fi
  done

  if rg -n --fixed-strings "Deprecated runtime path" "$deprecated_agent_file" >/dev/null; then
    pass "ralph-runner agent explicitly marked deprecated"
  else
    fail "ralph-runner agent must be marked deprecated"
  fi
}

check_status_semantics_contract() {
  echo "== Check: Status Semantics Contract =="
  require_file "$STATUS_SEMANTICS_FILE" || true

  if rg -n --fixed-strings "status-semantics.md" "contracts/ralph/core/linear-workflow.md" >/dev/null; then
    pass "linear-workflow references status semantics"
  else
    fail "linear-workflow missing status semantics reference"
  fi

  if rg -n --fixed-strings "status-semantics.md" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run contract references status semantics"
  else
    fail "ralph-run contract missing status semantics reference"
  fi

  if rg -n --fixed-strings "status-semantics.md" "commands/linear/audit-project.md" >/dev/null; then
    pass "audit-project references status semantics"
  else
    fail "audit-project missing status semantics reference"
  fi
}

check_issue_metadata_rubric_contract() {
  echo "== Check: Issue Metadata Rubric Contract =="
  require_file "$ISSUE_METADATA_RUBRIC_FILE" || true
  require_file "$METADATA_SCORER_SCRIPT" || true

  if rg -n --fixed-strings "issue-metadata-rubric.md" "contracts/ralph/core/commands/populate-project.md" >/dev/null \
    && rg -n --fixed-strings "issue-metadata-rubric.md" "contracts/ralph/core/commands/create-issue.md" >/dev/null \
    && rg -n --fixed-strings "issue-metadata-rubric.md" "contracts/ralph/core/commands/audit-project.md" >/dev/null; then
    pass "core command contracts reference issue metadata rubric"
  else
    fail "core command contracts missing issue metadata rubric references"
  fi

  if rg -n --fixed-strings "score-issue-metadata.sh" "commands/linear/populate-project.md" >/dev/null \
    && rg -n --fixed-strings "score-issue-metadata.sh" "commands/linear/create-issue.md" >/dev/null \
    && rg -n --fixed-strings "issue-metadata-rubric.md" "commands/linear/audit-project.md" >/dev/null; then
    pass "Linear command wrappers reference scorer and rubric checks"
  else
    fail "Linear command wrappers missing scorer/rubric references"
  fi
}

check_deterministic_scheduling_contract() {
  echo "== Check: Deterministic Scheduling Contract =="
  require_file "$RUN_LOG_TEMPLATE_FILE" || true

  if rg -n --fixed-strings "Deterministic Selection Policy" "contracts/ralph/core/commands/ralph-run.md" >/dev/null; then
    pass "ralph-run contract documents deterministic selection policy"
  else
    fail "ralph-run contract missing deterministic selection policy section"
  fi

  if rg -n --fixed-strings "RUN_SCHEDULE_DECISION" "$RALPH_RUN_SCRIPT" >/dev/null \
    && rg -n --fixed-strings "scheduleDecision" "$RALPH_RUN_SCRIPT" >/dev/null; then
    pass "ralph-run script emits scheduling progress and run-log rationale"
  else
    fail "ralph-run script missing scheduling rationale markers"
  fi

  if rg -n --fixed-strings "Deterministic Scheduling Inputs" "commands/linear/audit-project.md" >/dev/null; then
    pass "audit-project command includes deterministic scheduling input checks"
  else
    fail "audit-project command missing deterministic scheduling input checks"
  fi
}

check_codex_skill_boundary_routing() {
  echo "== Check: Codex Skill Boundary Routing =="
  require_file "$CODEX_SKILL_BOUNDARY_FILE" || true

  if rg -n --fixed-strings "Intent Routing Matrix" "$CODEX_SKILL_BOUNDARY_FILE" >/dev/null; then
    pass "codex skill boundary includes routing matrix"
  else
    fail "codex skill boundary missing intent routing matrix"
  fi

  if rg -n --fixed-strings "skill-boundary.md" "$CODEX_ADAPTER_FILE" >/dev/null; then
    pass "codex adapter references skill boundary contract"
  else
    fail "codex adapter must reference skill boundary contract"
  fi

  local ralph_skills=(
    "skills/ralph-create-project/SKILL.md"
    "skills/ralph-populate-project/SKILL.md"
    "skills/ralph-generate-prd-from-project/SKILL.md"
    "skills/ralph-audit-project/SKILL.md"
    "skills/ralph-run/SKILL.md"
  )
  local skill_file=""
  for skill_file in "${ralph_skills[@]}"; do
    require_file "$skill_file" || true
    if rg -n --fixed-strings "## Intent Boundary" "$skill_file" >/dev/null; then
      pass "intent boundary section present: ${skill_file}"
    else
      fail "intent boundary section missing: ${skill_file}"
    fi
    if rg -n --fixed-strings "Do not use for Linear PM triage/admin workflows." "$skill_file" >/dev/null; then
      pass "linear PM exclusion present: ${skill_file}"
    else
      fail "linear PM exclusion missing: ${skill_file}"
    fi
  done

  require_file "$ADAPTER_SMOKE_RUN_FILE" || true
  if rg -n --fixed-strings "scripts/check-ralph-drift.sh" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null; then
    pass "adapter smoke-run includes reproducible drift-check procedure"
  else
    fail "adapter smoke-run missing reproducible drift-check procedure"
  fi

  if rg -n --fixed-strings "ralph-create-project" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null \
    && rg -n --fixed-strings "ralph-populate-project" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null \
    && rg -n --fixed-strings "ralph-generate-prd-from-project" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null \
    && rg -n --fixed-strings "ralph-audit-project" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null \
    && rg -n --fixed-strings "ralph-run" "$ADAPTER_SMOKE_RUN_FILE" >/dev/null; then
    pass "adapter smoke-run covers all Codex wrapper skills"
  else
    fail "adapter smoke-run missing one or more Codex wrapper skills"
  fi
}

print_story_diff() {
  local file="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  perl -pe 's/\bStory\b/Issue/g' "$file" > "$tmp_file"
  echo "---- Suggested diff for ${file} ----"
  diff -u "$file" "$tmp_file" || true
  rm -f "$tmp_file"
}

check_terminology_drift() {
  echo "== Check: Forbidden Terminology Drift =="
  local targets=(
    "contracts/ralph/core"
    "contracts/ralph/adapters/mapping.md"
    "contracts/ralph/adapters/cursor/README.md"
    "contracts/ralph/adapters/codex/README.md"
    "skills/ralph-create-project/SKILL.md"
    "skills/ralph-populate-project/SKILL.md"
    "skills/ralph-generate-prd-from-project/SKILL.md"
    "skills/ralph-audit-project/SKILL.md"
    "skills/ralph-run/SKILL.md"
  )

  local offenders=()
  local path
  for path in "${targets[@]}"; do
    if [ -e "$path" ] && rg -n '\bStory\b' "$path" >/dev/null; then
      offenders+=("$path")
    fi
  done

  if [ "${#offenders[@]}" -eq 0 ]; then
    pass "no forbidden terminology drift detected"
    return
  fi

  fail "forbidden terminology detected (use 'Issue' for Linear work items)"
  local offender
  for offender in "${offenders[@]}"; do
    rg -n '\bStory\b' "$offender" || true
    print_story_diff "$offender"
  done
}

echo "=== Ralph Drift Guardrails ==="
require_file "$MAPPING_FILE" || true
require_file "$CURSOR_ADAPTER_FILE" || true
require_file "$CODEX_ADAPTER_FILE" || true
require_file "$SHARED_VALIDATIONS_FILE" || true
require_file "$SCHEMA_FILE" || true
require_file "$STATUS_SEMANTICS_FILE" || true
require_file "$ISSUE_METADATA_RUBRIC_FILE" || true
require_file "$CLI_CONTRACT_FILE" || true
require_file "$ISSUE_CREATION_CONTRACT_FILE" || true
require_file "$REVIEW_FEEDBACK_CONTRACT_FILE" || true
require_file "$RETROSPECTIVE_CONTRACT_FILE" || true
require_file "$PLAN_MODE_CONTRACT_FILE" || true
require_file "$PLAN_MODE_SMOKE_FILE" || true
require_file "$NO_DRIFT_RULES_FILE" || true
require_file "$ADAPTER_SMOKE_RUN_FILE" || true
require_file "$BOOTSTRAP_SURFACES_SCRIPT" || true
require_file "$CLI_RESULT_SCHEMA_FILE" || true
require_file "$RALPH_RUN_SCRIPT" || true
require_file "$ISSUE_INTENT_ENQUEUE_SCRIPT" || true
require_file "$ISSUE_INTENT_WORKER_SCRIPT" || true
require_file "$REVIEW_FEEDBACK_SWEEP_SCRIPT" || true
require_file "$RETROSPECTIVE_SCRIPT" || true
require_file "$RETROSPECTIVE_IMPROVEMENT_SCRIPT" || true
require_file "$METADATA_SCORER_SCRIPT" || true
require_file "$RUN_LOG_TEMPLATE_FILE" || true
require_file "$CODEX_SKILL_BOUNDARY_FILE" || true

check_command_parity
check_schema_parity_and_freshness
check_plan_mode_parity
check_adapter_no_drift_rules
check_dual_surface_bootstrap_contract
check_status_semantics_contract
check_issue_metadata_rubric_contract
check_deterministic_scheduling_contract
check_cli_issue_contract
check_issue_creation_delegation_contract
check_review_feedback_sweep_contract
check_retrospective_contract
check_terminal_runtime_boundary
check_codex_skill_boundary_routing
check_terminology_drift

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS all Ralph drift checks passed"
  exit 0
fi

echo "RESULT FAIL Ralph drift checks failed: ${FAILURES}"
exit 1
