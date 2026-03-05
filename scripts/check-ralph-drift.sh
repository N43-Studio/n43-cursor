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
SHARED_VALIDATIONS_FILE="contracts/ralph/core/shared-validations.md"
SCHEMA_FILE="contracts/ralph/core/schema/normalized-result.schema.json"

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

check_command_parity
check_schema_parity_and_freshness
check_terminology_drift

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS all Ralph drift checks passed"
  exit 0
fi

echo "RESULT FAIL Ralph drift checks failed: ${FAILURES}"
exit 1
