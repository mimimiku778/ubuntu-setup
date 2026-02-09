#!/bin/bash
# claude-root-patch.sh
# Sets up the `claudex` command that runs Claude Code with sudo NOPASSWD bypass.
# Works with both traditional sudo and sudo-rs.
#
# Usage:
#   bash claude-root-patch.sh
#
# What it does:
#   1. Adds a `claudex` shell function to ~/.bashrc
#   2. The function creates a temporary NOPASSWD sudoers entry on launch
#   3. Claude Code runs with --dangerously-skip-permissions
#   4. The sudoers entry is automatically removed when Claude exits (or on Ctrl+C)
#
# Requirements:
#   - Claude Code installed (~/.local/bin/claude)
#   - User must have sudo privileges (password prompted once on each launch)

set -euo pipefail

BASHRC="$HOME/.bashrc"

# --- Install Claude Code if not present ---
if ! command -v claude &>/dev/null; then
    echo "[INFO] Claude Code not found. Installing..."
    curl -fsSL https://claude.ai/install.sh | bash

    # Add ~/.local/bin to PATH if not already included
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        if ! grep -qF '.local/bin' "$BASHRC" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
            echo "[OK] Added ~/.local/bin to PATH in $BASHRC"
        fi
    fi

    # Verify installation succeeded
    if ! command -v claude &>/dev/null; then
        echo "Error: Claude Code installation failed." >&2
        exit 1
    fi
    echo "[OK] Claude Code installed successfully"
fi

# --- Add claudex function to .bashrc (idempotent) ---
if grep -qF 'claudex()' "$BASHRC" 2>/dev/null; then
    echo "[SKIP] claudex function already exists in $BASHRC"
else
    cat >> "$BASHRC" << 'BASHRC_BLOCK'

# Claude Code with sudo password bypass (session only)
claudex() {
    local sudoers_file="/etc/sudoers.d/claudex-temp"
    echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee "$sudoers_file" > /dev/null || return 1
    sudo chmod 440 "$sudoers_file"
    trap 'sudo rm -f "$sudoers_file"' EXIT INT TERM
    claude --dangerously-skip-permissions "$@"
    sudo rm -f "$sudoers_file"
    trap - EXIT INT TERM
}
BASHRC_BLOCK
    echo "[OK] Added claudex function to $BASHRC"
fi

echo ""
echo "Done! Run the following to start using it:"
echo "  source ~/.bashrc"
echo "  claudex"
