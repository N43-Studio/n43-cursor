#!/usr/bin/env bash
#
# Bootstrap Ralph workflow links for both Cursor and Codex surfaces.
#
# Modes:
#   verify (default): report pass/fail for all required links
#   install: create/repair required symlinks where safe
#
# Usage:
#   scripts/bootstrap-ralph-surfaces.sh
#   scripts/bootstrap-ralph-surfaces.sh install
#   scripts/bootstrap-ralph-surfaces.sh verify --cursor-dir /path/.cursor --codex-home /path/.codex
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="verify"
if [ "${1:-}" = "install" ] || [ "${1:-}" = "verify" ]; then
  MODE="$1"
  shift
fi

CURSOR_DIR="$REPO_ROOT/.cursor"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DRY_RUN="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --cursor-dir)
      shift
      CURSOR_DIR="${1:-}"
      ;;
    --codex-home)
      shift
      CODEX_HOME="${1:-}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --help|-h)
      cat <<'EOF'
Usage: bootstrap-ralph-surfaces.sh [install|verify] [options]

Options:
  --cursor-dir <path>   Cursor workspace directory (default: <repo>/.cursor)
  --codex-home <path>   Codex home directory (default: $CODEX_HOME or ~/.codex)
  --dry-run             Show install actions without mutating filesystem
EOF
      exit 0
      ;;
    *)
      echo "FAIL unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

if [ -z "$CURSOR_DIR" ] || [ -z "$CODEX_HOME" ]; then
  echo "FAIL invalid empty path argument"
  exit 1
fi

CODEX_SKILLS_DIR="$CODEX_HOME/skills"
FAILURES=0
CHECKED_LINKS=0
PASS_LINKS=0
REPAIRED_LINKS=0
CREATED_LINKS=0
FAILED_LINKS=0

CURSOR_LINK_NAMES=(agents commands references rules skills)
RALPH_SKILLS=(
  ralph-create-project
  ralph-populate-project
  ralph-generate-prd-from-project
  ralph-audit-project
  ralph-run
)

print_header() {
  echo "=== Ralph Dual-Surface Bootstrap ==="
  echo "Mode: $MODE"
  echo "Repo: $REPO_ROOT"
  echo "Cursor dir: $CURSOR_DIR"
  echo "Codex home: $CODEX_HOME"
  [ "$DRY_RUN" = "true" ] && echo "Dry run: true"
  echo ""
}

record_fail() {
  FAILURES=$((FAILURES + 1))
}

run_or_echo() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN $*"
    return 0
  fi
  "$@"
}

ensure_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    echo "PASS dir exists: $dir"
    return 0
  fi
  if [ "$MODE" = "verify" ]; then
    echo "FAIL missing directory: $dir"
    record_fail
    return 1
  fi
  if run_or_echo mkdir -p "$dir"; then
    echo "PASS created directory: $dir"
  else
    echo "FAIL unable to create directory: $dir"
    record_fail
    return 1
  fi
}

verify_or_repair_link() {
  local link_path="$1"
  local target_path="$2"
  CHECKED_LINKS=$((CHECKED_LINKS + 1))

  echo "EXPECT $link_path -> $target_path"

  if [ -L "$link_path" ]; then
    local current_target
    current_target="$(readlink "$link_path")"
    if [ "$current_target" = "$target_path" ]; then
      echo "PASS link ok: $link_path"
      PASS_LINKS=$((PASS_LINKS + 1))
      return 0
    fi
    if [ "$MODE" = "verify" ]; then
      echo "FAIL wrong target: $link_path -> $current_target"
      record_fail
      FAILED_LINKS=$((FAILED_LINKS + 1))
      return 1
    fi
    if run_or_echo rm "$link_path" && run_or_echo ln -s "$target_path" "$link_path"; then
      echo "PASS repaired link: $link_path"
      REPAIRED_LINKS=$((REPAIRED_LINKS + 1))
      return 0
    fi
    echo "FAIL unable to repair link: $link_path"
    record_fail
    FAILED_LINKS=$((FAILED_LINKS + 1))
    return 1
  fi

  if [ -e "$link_path" ]; then
    echo "FAIL path exists and is not a symlink: $link_path"
    record_fail
    FAILED_LINKS=$((FAILED_LINKS + 1))
    return 1
  fi

  if [ "$MODE" = "verify" ]; then
    echo "FAIL missing symlink: $link_path"
    record_fail
    FAILED_LINKS=$((FAILED_LINKS + 1))
    return 1
  fi

  if run_or_echo ln -s "$target_path" "$link_path"; then
    echo "PASS created link: $link_path"
    CREATED_LINKS=$((CREATED_LINKS + 1))
    return 0
  fi

  echo "FAIL unable to create link: $link_path"
  record_fail
  FAILED_LINKS=$((FAILED_LINKS + 1))
  return 1
}

bootstrap_cursor_links() {
  echo "--- Cursor Surface ---"
  ensure_dir "$CURSOR_DIR"
  local name=""
  for name in "${CURSOR_LINK_NAMES[@]}"; do
    verify_or_repair_link "$CURSOR_DIR/$name" "$REPO_ROOT/$name"
  done
  echo ""
}

bootstrap_codex_links() {
  echo "--- Codex Surface ---"
  ensure_dir "$CODEX_SKILLS_DIR"
  local skill=""
  for skill in "${RALPH_SKILLS[@]}"; do
    verify_or_repair_link "$CODEX_SKILLS_DIR/$skill" "$REPO_ROOT/skills/$skill"
  done
  echo ""
}

print_header
bootstrap_cursor_links
bootstrap_codex_links
echo "RESULT_SUMMARY mode=$MODE checked_links=$CHECKED_LINKS pass_links=$PASS_LINKS repaired_links=$REPAIRED_LINKS created_links=$CREATED_LINKS failed_links=$FAILED_LINKS dry_run=$DRY_RUN"

if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT PASS all required links are valid"
  exit 0
fi

echo "RESULT FAIL issues detected: $FAILURES"
exit 1
