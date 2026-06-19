#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${STATE_FILE:-$DOTFILES_DIR/.install_state}"
ERRORS_FILE="${ERRORS_FILE:-$DOTFILES_DIR/.install_errors}"
LOG_FILE="${LOG_FILE:-$DOTFILES_DIR/.install.log}"

# apt source paths (overridable so tests can target temp dirs)
APT_SOURCES_LIST="${APT_SOURCES_LIST:-/etc/apt/sources.list}"
APT_SOURCES_DIR="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"

# Directory of per-program scripts (overridable so tests can target temp dirs)
PROGRAMS_DIR="${PROGRAMS_DIR:-$DOTFILES_DIR/scripts/programs}"

declare -a STEPS_OK=()
declare -a STEPS_SKIP=()
declare -a STEPS_FAIL=()

# Install plan: parallel arrays describing every selectable item.
# ITEM_ON holds the current selection (1 = install, 0 = skip).
declare -a ITEM_KEYS=()
declare -a ITEM_LABELS=()
declare -a ITEM_TYPES=()
declare -a ITEM_SCRIPTS=()
declare -a ITEM_ON=()

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

function system_update {
    echo "[SYS] Running apt update..."
    sudo apt update && sudo apt full-upgrade -y
}

# Install stow and apply the dotfile symlinks. Always runs regardless of the
# selection — it is the whole point of the repo and is idempotent.
function apply_stow {
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

# --- Selection plan ---

# Populate the ITEM_* arrays: two built-in phases followed by one entry per
# program script discovered in PROGRAMS_DIR. Everything starts selected.
function build_plan {
    ITEM_KEYS=(); ITEM_LABELS=(); ITEM_TYPES=(); ITEM_SCRIPTS=(); ITEM_ON=()

    ITEM_KEYS+=("system_update"); ITEM_LABELS+=("system update (apt update + full-upgrade)"); ITEM_TYPES+=("phase"); ITEM_SCRIPTS+=(""); ITEM_ON+=(1)
    ITEM_KEYS+=("base");          ITEM_LABELS+=("base packages (zsh, curl, vim, tmux...)");    ITEM_TYPES+=("phase"); ITEM_SCRIPTS+=(""); ITEM_ON+=(1)

    local script name
    for script in "$PROGRAMS_DIR"/*.sh; do
        [ -f "$script" ] || continue
        name="$(basename "$script" .sh)"
        ITEM_KEYS+=("$name"); ITEM_LABELS+=("$name"); ITEM_TYPES+=("program"); ITEM_SCRIPTS+=("$script"); ITEM_ON+=(1)
    done
}

# Set every item's selection to $1 (0 or 1).
function set_all {
    local v="$1" i
    for i in "${!ITEM_ON[@]}"; do ITEM_ON[$i]="$v"; done
}

# Toggle the item at the 1-based position $1. Ignores out-of-range/non-numeric.
function toggle_item {
    local n="$1" idx
    [[ "$n" =~ ^[0-9]+$ ]] || return 0
    idx=$((n - 1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "${#ITEM_ON[@]}" ] || return 0
    if [ "${ITEM_ON[$idx]}" -eq 1 ]; then ITEM_ON[$idx]=0; else ITEM_ON[$idx]=1; fi
}

# Return 0 if the item with key $1 is currently selected.
function is_selected {
    local key="$1" i
    for i in "${!ITEM_KEYS[@]}"; do
        if [ "${ITEM_KEYS[$i]}" = "$key" ]; then
            [ "${ITEM_ON[$i]}" -eq 1 ] && return 0 || return 1
        fi
    done
    return 1
}

function render_menu {
    local i mark
    echo ""
    echo "Select what to install (toggle by number, Enter to confirm):"
    echo ""
    echo "  Phases:"
    for i in "${!ITEM_KEYS[@]}"; do
        [ "${ITEM_TYPES[$i]}" = "phase" ] || continue
        [ "${ITEM_ON[$i]}" -eq 1 ] && mark="x" || mark=" "
        printf "  [%s] %2d) %s\n" "$mark" "$((i + 1))" "${ITEM_LABELS[$i]}"
    done
    echo ""
    echo "  Programs:"
    for i in "${!ITEM_KEYS[@]}"; do
        [ "${ITEM_TYPES[$i]}" = "program" ] || continue
        [ "${ITEM_ON[$i]}" -eq 1 ] && mark="x" || mark=" "
        printf "  [%s] %2d) %s\n" "$mark" "$((i + 1))" "${ITEM_LABELS[$i]}"
    done
    echo ""
    echo "  a) all   n) none   q) quit   Enter) confirm"
}

# Interactive toggle loop. Accepts space-separated numbers, a/n/q, or Enter.
function select_menu {
    local line tok
    while true; do
        render_menu
        printf '> '
        if ! read -r line; then line="q"; fi
        case "$line" in
            "") return 0 ;;
            a|A|all)  set_all 1 ;;
            n|N|none) set_all 0 ;;
            q|Q|quit) echo "Aborted — nothing installed."; exit 0 ;;
            *) for tok in $line; do toggle_item "$tok"; done ;;
        esac
    done
}

# Execute the selected phases and program scripts in order.
function run_plan {
    local i
    for i in "${!ITEM_KEYS[@]}"; do
        [ "${ITEM_ON[$i]}" -eq 1 ] || continue
        case "${ITEM_TYPES[$i]}" in
            phase)
                case "${ITEM_KEYS[$i]}" in
                    system_update) system_update ;;
                    base)          install_base ;;
                esac
                ;;
            program)
                chmod u+x "${ITEM_SCRIPTS[$i]}"
                run_step "${ITEM_KEYS[$i]}" "${ITEM_SCRIPTS[$i]}"
                ;;
        esac
    done

    # Final cleanup only makes sense if we touched the system packages.
    if is_selected system_update; then
        sudo apt upgrade -y
        sudo apt autoremove -y
    fi
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

function usage {
    cat <<EOF
Usage: bash scripts/install.sh [options]

Pick which phases and programs to install. With no options and an interactive
terminal, an interactive menu is shown. Stow symlinks are always applied.

Options:
  -a, --all      Install everything without prompting (required when there is
                 no interactive terminal, e.g. piped input or CI).
  -h, --help     Show this help and exit.
EOF
}

# --- Main (only runs when executed directly, not sourced) ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    RUN_ALL=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--all|-y|--yes) RUN_ALL=1 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done

    echo "Current working directory is: $(pwd)"

    # Clear errors file; append run separator to log
    > "$ERRORS_FILE"
    echo "" >> "$LOG_FILE"
    echo "=== Install run: $(date) ===" >> "$LOG_FILE"

    # Disabling the cdrom source and applying symlinks always happen first.
    disable_cdrom_source

    build_plan
    if [ "$RUN_ALL" -eq 1 ]; then
        set_all 1
    elif [ -t 0 ]; then
        select_menu
    else
        echo "No interactive terminal detected. Re-run with --all to install everything." >&2
        exit 2
    fi

    apply_stow
    run_plan

    print_summary
fi
