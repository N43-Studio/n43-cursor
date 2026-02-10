#!/usr/bin/env bash
set -euo pipefail

# Cursor Workflow Setup Script
# Installs shared workflow files from n43-cursor into ~/.cursor/ (global).
# Designed to be called from a devcontainer's postCreateCommand.
#
# Usage:
#   /opt/n43-cursor/scripts/setup.sh              # Default: symlink mode
#   /opt/n43-cursor/scripts/setup.sh --dry-run    # Preview without changes
#   /opt/n43-cursor/scripts/setup.sh --copy       # Copy instead of symlink

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CURSOR_DIR="$HOME/.cursor"

# Parse flags
DRY_RUN=false
COPY_MODE=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --copy)    COPY_MODE=true ;;
        --help|-h)
            echo "Usage: setup.sh [--dry-run] [--copy]"
            echo "  --dry-run  Preview changes without making them"
            echo "  --copy     Copy files instead of creating symlinks"
            exit 0
            ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

MODE="symlink"
$COPY_MODE && MODE="copy"

echo "=== Cursor Workflow Setup ==="
echo "Workflow source: $WORKFLOW_DIR"
echo "Target:          $CURSOR_DIR"
echo "Mode:            $MODE"
$DRY_RUN && echo "DRY RUN:         yes (no changes will be made)"
echo ""

# Track results
LINKED=()
SKIPPED=()

# --- Helper Functions ---

install_file() {
    local src="$1"
    local dest="$2"

    if [ -L "$dest" ]; then
        # Already a symlink — update it
        if $DRY_RUN; then
            LINKED+=("$(basename "$dest") (would update)")
            return
        fi
        rm "$dest"
    elif [ -f "$dest" ]; then
        # Real file exists — don't overwrite (project override)
        SKIPPED+=("$(basename "$dest") (project override)")
        return
    fi

    if $DRY_RUN; then
        LINKED+=("$(basename "$dest")")
        return
    fi

    if $COPY_MODE; then
        cp "$src" "$dest"
        LINKED+=("$(basename "$dest") (copied)")
    else
        # Compute relative path from dest's directory to src
        local rel_src
        rel_src="$(python3 -c "import os.path; print(os.path.relpath('$src', os.path.dirname('$dest')))")"
        ln -s "$rel_src" "$dest"
        LINKED+=("$(basename "$dest")")
    fi
}

install_directory_contents() {
    local src_dir="$1"
    local dest_dir="$2"

    $DRY_RUN || mkdir -p "$dest_dir"

    for src_file in "$src_dir"/*; do
        [ -e "$src_file" ] || continue
        local basename
        basename="$(basename "$src_file")"

        if [ -d "$src_file" ]; then
            install_directory_contents "$src_file" "$dest_dir/$basename"
        else
            install_file "$src_file" "$dest_dir/$basename"
        fi
    done
}

# --- Create ~/.cursor directories ---

if ! $DRY_RUN; then
    mkdir -p "$CURSOR_DIR/agents"
    mkdir -p "$CURSOR_DIR/commands"
    mkdir -p "$CURSOR_DIR/rules"
    mkdir -p "$CURSOR_DIR/skills"
    mkdir -p "$CURSOR_DIR/references"
fi

# --- Link/copy agents ---

echo "Installing agents..."
install_directory_contents "$WORKFLOW_DIR/agents" "$CURSOR_DIR/agents"

# --- Link/copy commands ---

echo "Installing commands..."
install_directory_contents "$WORKFLOW_DIR/commands" "$CURSOR_DIR/commands"

# --- Link/copy rules ---

echo "Installing rules..."
for rule_file in "$WORKFLOW_DIR/rules"/*.mdc; do
    [ -e "$rule_file" ] || continue
    install_file "$rule_file" "$CURSOR_DIR/rules/$(basename "$rule_file")"
done

# --- Link/copy skills ---

echo "Installing skills..."
install_directory_contents "$WORKFLOW_DIR/skills" "$CURSOR_DIR/skills"

# --- Link/copy references ---

echo "Installing references..."
install_directory_contents "$WORKFLOW_DIR/references" "$CURSOR_DIR/references"

# --- Report ---

echo ""
echo "=== Setup Complete ==="
$DRY_RUN && echo "(DRY RUN — no changes were made)"
echo ""

if [ ${#LINKED[@]} -gt 0 ]; then
    echo "Installed (${#LINKED[@]}):"
    for item in "${LINKED[@]}"; do
        echo "  ✓ $item"
    done
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "Skipped (${#SKIPPED[@]}):"
    for item in "${SKIPPED[@]}"; do
        echo "  ⊘ $item"
    done
fi

echo ""
echo "Next steps:"
echo "  1. Shared files are now available in $CURSOR_DIR"
echo "  2. Project-specific config goes in your project's .cursor/ directory"
echo "  3. To override a shared file, create it in the project's .cursor/"
