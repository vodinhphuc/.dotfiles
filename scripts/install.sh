#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${STATE_FILE:-$DOTFILES_DIR/.install_state}"
ERRORS_FILE="${ERRORS_FILE:-$DOTFILES_DIR/.install_errors}"
LOG_FILE="${LOG_FILE:-$DOTFILES_DIR/.install.log}"

# apt source paths (overridable so tests can target temp dirs)
APT_SOURCES_LIST="${APT_SOURCES_LIST:-/etc/apt/sources.list}"
APT_SOURCES_DIR="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"

declare -a STEPS_OK=()
declare -a STEPS_SKIP=()
declare -a STEPS_FAIL=()

# --- Functions ---

function install_pkg {
    if ! command -v "$1" &>/dev/null; then
        echo "Installing: $1..."
        sudo apt install -y "$1"
    else
        echo "Already installed: $1"
    fi
}

function run_step {
    local name="$1"
    local script="$2"

    if grep -qx "$name" "$STATE_FILE" 2>/dev/null; then
        echo "[SKIP] $name"
        STEPS_SKIP+=("$name")
        return
    fi

    echo "[RUN]  $name..."
    if (bash "$script" >> "$LOG_FILE" 2>&1); then
        echo "$name" >> "$STATE_FILE"
        echo "[OK]   $name"
        STEPS_OK+=("$name")
    else
        echo "[FAIL] $name (see .install.log)"
        echo "$name" >> "$ERRORS_FILE"
        STEPS_FAIL+=("$name")
    fi
}

# A fresh Ubuntu install leaves the install media as an apt source
# (`deb cdrom:[...]` / `file:/cdrom`). Once the ISO/USB is unmounted, every
# `apt update` errors out ("no longer has a Release file"), which aborts any
# program script that refreshes apt (e.g. glow.sh). Disable it up front.
function disable_cdrom_source {
    echo "[SYS] Disabling CD-ROM apt sources (if any)..."
    # Legacy one-line format (.list): comment out any deb line that uses cdrom
    for f in "$APT_SOURCES_LIST" "$APT_SOURCES_DIR"/*.list; do
        [ -f "$f" ] || continue
        if grep -Eq '^[[:space:]]*deb.*cdrom' "$f"; then
            sudo sed -i -E '/^[[:space:]]*deb.*cdrom/ s/^/#/' "$f"
            echo "  disabled cdrom entries in $f"
        fi
    done
    # deb822 format (.sources): disable any stanza file that references cdrom
    for f in "$APT_SOURCES_DIR"/*.sources; do
        [ -f "$f" ] || continue
        if grep -Eiq 'cdrom|file:/cdrom' "$f"; then
            sudo mv "$f" "$f.disabled"
            echo "  disabled cdrom source file $f"
        fi
    done
}

function fix_system {
    disable_cdrom_source

    echo "[SYS] Running apt update..."
    sudo apt update && sudo apt full-upgrade -y

    echo "[SYS] Installing stow..."
    install_pkg stow

    echo "[SYS] Applying stow symlinks..."
    [ -f ~/.bashrc ] && [ ! -f ~/.bashrc.bk ] && mv ~/.bashrc ~/.bashrc.bk
    stow --adopt . && git -C "$DOTFILES_DIR" checkout .
}

function install_base {
    echo "[BASE] Installing base packages..."
    for pkg in chrome-gnome-shell curl htop tree vim wget tmux zsh nvtop; do
        install_pkg "$pkg"
    done
    [ "$SHELL" = "/usr/bin/zsh" ] || chsh -s /usr/bin/zsh
}

function print_summary {
    local fail_count=${#STEPS_FAIL[@]}
    echo ""
    echo "=========================================="
    echo "  Install Summary"
    echo "=========================================="
    for s in "${STEPS_OK[@]+"${STEPS_OK[@]}"}";   do echo "  [OK]   $s"; done
    for s in "${STEPS_SKIP[@]+"${STEPS_SKIP[@]}"}"; do echo "  [SKIP] $s"; done
    for s in "${STEPS_FAIL[@]+"${STEPS_FAIL[@]}"}"; do echo "  [FAIL] $s"; done
    echo "=========================================="
    if [ "$fail_count" -gt 0 ]; then
        echo "  $fail_count failed. Check $LOG_FILE"
        echo "=========================================="
        return 1
    else
        echo "  All steps completed successfully."
        echo "=========================================="
    fi
}

# --- Main (only runs when executed directly, not sourced) ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Current working directory is: $(pwd)"

    # Clear errors file; append run separator to log
    > "$ERRORS_FILE"
    echo "" >> "$LOG_FILE"
    echo "=== Install run: $(date) ===" >> "$LOG_FILE"

    fix_system
    install_base

    chmod u+x "$DOTFILES_DIR"/scripts/programs/*.sh
    for script in "$DOTFILES_DIR"/scripts/programs/*.sh; do
        name="$(basename "$script" .sh)"
        run_step "$name" "$script"
    done

    sudo apt upgrade -y
    sudo apt autoremove -y

    print_summary
fi
