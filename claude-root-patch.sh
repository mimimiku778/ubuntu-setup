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

# --- Remove old claudex function if present ---
if grep -qF 'claudex()' "$BASHRC" 2>/dev/null; then
    # Remove the old function block (from comment line to closing brace)
    sed -i '/^# Claude Code with sudo password bypass/,/^}/d' "$BASHRC"
    # Remove any blank lines left behind (collapse multiple blank lines to one)
    sed -i '/^$/N;/^\n$/d' "$BASHRC"
    echo "[OK] Removed old claudex function from $BASHRC"
fi

# --- Add claudex function to .bashrc ---
cat >> "$BASHRC" << 'BASHRC_BLOCK'

# Claude Code with sudo password bypass (session only)
claudex() {
    # Check for NoNewPrivs — relaunch via systemd-run to get a clean process
    local nnp
    nnp=$(grep -oP 'NoNewPrivs:\s*\K\d' /proc/self/status 2>/dev/null || echo "0")
    if [ "$nnp" = "1" ]; then
        echo "[INFO] NoNewPrivs detected — relaunching via systemd-run..."
        local escaped_args=""
        for arg in "$@"; do
            escaped_args+="$(printf '%q ' "$arg")"
        done
        systemd-run --user --quiet --pty --wait \
            -p WorkingDirectory="$(pwd)" \
            -p Environment="PATH=$PATH" \
            -- bash -ic "claudex ${escaped_args}"
        return $?
    fi

    # Find a working sudo binary (sudo-rs may be broken via alternatives)
    local SUDO="sudo"
    if ! sudo -V &>/dev/null 2>&1 && [ -x /usr/bin/sudo.ws ]; then
        SUDO="/usr/bin/sudo.ws"
    fi

    local sudoers_file="/etc/sudoers.d/claudex-temp"
    echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | $SUDO tee "$sudoers_file" > /dev/null || return 1
    $SUDO chmod 440 "$sudoers_file"
    trap "$SUDO rm -f '$sudoers_file'" EXIT INT TERM
    claude --dangerously-skip-permissions "$@"
    $SUDO rm -f "$sudoers_file"
    trap - EXIT INT TERM
}
BASHRC_BLOCK
echo "[OK] Added claudex function to $BASHRC"

echo ""
echo "Done! Run the following to start using it:"
echo "  source ~/.bashrc"
echo "  claudex"
