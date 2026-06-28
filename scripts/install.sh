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

# Install target: "native" (a normal Ubuntu desktop) or "wsl" (Windows
# Subsystem for Linux). On WSL there is no GPU/sensors and no GNOME desktop,
# and snap/systemd are unreliable, so desktop/hardware programs are skipped
# by default. Resolved at runtime; "native" is a safe default for sourcing.
ENVIRONMENT="${ENVIRONMENT:-native}"

# Program scripts that only make sense on a native desktop. They stay visible
# in the menu but start deselected on WSL (the user can still toggle them on).
NATIVE_ONLY_PROGRAMS=" docker fan_control ibus_unikey terminator visual_code "

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
    echo "[BASE] Installing base packages (target: $ENVIRONMENT)..."
    local pkgs=(curl htop tree vim wget tmux zsh)
    # GNOME shell integration and the GPU monitor are desktop-only.
    if [ "$ENVIRONMENT" = "native" ]; then
        pkgs+=(chrome-gnome-shell nvtop)
    fi
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
    [ "$SHELL" = "/usr/bin/zsh" ] || chsh -s /usr/bin/zsh
}

# --- Install target detection ---

# Echo "wsl" when running under Windows Subsystem for Linux, else "native".
function detect_environment {
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo "wsl"
    else
        echo "native"
    fi
}

# True if program key $1 is desktop/hardware-only (skipped by default on WSL).
function is_native_only {
    [[ "$NATIVE_ONLY_PROGRAMS" == *" $1 "* ]]
}

# Interactive prompt to confirm/override the detected install target.
function choose_environment {
    local detected="$1" line
    echo ""
    echo "Install target (detected: $detected):"
    echo "  1) Native Ubuntu (desktop)"
    echo "  2) WSL (Windows Subsystem for Linux)"
    printf '> '
    if ! read -r line; then line=""; fi
    case "$line" in
        1) ENVIRONMENT="native" ;;
        2) ENVIRONMENT="wsl" ;;
        *) ENVIRONMENT="$detected" ;;
    esac
    echo "Target: $ENVIRONMENT"
}

# --- Selection plan ---

# Populate the ITEM_* arrays: two built-in phases followed by one entry per
# program script discovered in PROGRAMS_DIR. Defaults respect ENVIRONMENT:
# desktop/hardware-only programs start deselected on WSL.
function build_plan {
    ITEM_KEYS=(); ITEM_LABELS=(); ITEM_TYPES=(); ITEM_SCRIPTS=(); ITEM_ON=()

    ITEM_KEYS+=("system_update"); ITEM_LABELS+=("system update (apt update + full-upgrade)"); ITEM_TYPES+=("phase"); ITEM_SCRIPTS+=(""); ITEM_ON+=(1)
    ITEM_KEYS+=("base");          ITEM_LABELS+=("base packages (zsh, curl, vim, tmux...)");    ITEM_TYPES+=("phase"); ITEM_SCRIPTS+=(""); ITEM_ON+=(1)

    local script name label on
    for script in "$PROGRAMS_DIR"/*.sh; do
        [ -f "$script" ] || continue
        name="$(basename "$script" .sh)"
        label="$name"
        on=1
        if is_native_only "$name"; then
            label="$name (desktop/native)"
            [ "$ENVIRONMENT" = "wsl" ] && on=0
        fi
        ITEM_KEYS+=("$name"); ITEM_LABELS+=("$label"); ITEM_TYPES+=("program"); ITEM_SCRIPTS+=("$script"); ITEM_ON+=("$on")
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

# Build the lines to display, into MENU_OUT. A header precedes each group
# (Phases, Programs); the highlighted row (index $CURSOR) gets a ❯ pointer.
# Line count stays constant across redraws so select_menu can overwrite in place.
function _menu_compose {
    MENU_OUT=()
    MENU_OUT+=("Select what to install  (↑/↓ move · space toggle · a/n all/none · enter confirm · q quit)")
    MENU_OUT+=("")
    local i mark pointer lasttype=""
    for i in "${!ITEM_KEYS[@]}"; do
        if [ "${ITEM_TYPES[$i]}" != "$lasttype" ]; then
            [ -n "$lasttype" ] && MENU_OUT+=("")
            lasttype="${ITEM_TYPES[$i]}"
            [ "$lasttype" = "phase" ] && MENU_OUT+=("  Phases") || MENU_OUT+=("  Programs")
        fi
        [ "${ITEM_ON[$i]}" -eq 1 ] && mark="x" || mark=" "
        [ "$i" -eq "$CURSOR" ] && pointer="❯" || pointer=" "
        MENU_OUT+=("  $pointer [$mark] ${ITEM_LABELS[$i]}")
    done
}

# Interactive checklist: arrow keys (or j/k) move, space toggles, a/n select
# all/none, Enter confirms, q aborts. Redraws in place over a real terminal.
function select_menu {
    local total=${#ITEM_KEYS[@]} key rest first=1 line
    [ "$total" -gt 0 ] || return 0
    CURSOR=0
    printf '\033[?25l'                                   # hide the terminal cursor
    while true; do
        _menu_compose
        [ "$first" -eq 1 ] && first=0 || printf '\033[%dA' "${#MENU_OUT[@]}"
        for line in "${MENU_OUT[@]}"; do printf '\033[2K%s\n' "$line"; done
        IFS= read -rsn1 key || key=""                    # EOF -> "" -> confirm
        case "$key" in
            $'\x1b')                                     # escape sequence (arrow keys)
                read -rsn2 -t 0.05 rest || rest=""
                case "$rest" in
                    *A) CURSOR=$(( (CURSOR - 1 + total) % total )) ;;   # up
                    *B) CURSOR=$(( (CURSOR + 1) % total )) ;;           # down
                esac ;;
            ' ')  toggle_item "$((CURSOR + 1))" ;;
            k|K)  CURSOR=$(( (CURSOR - 1 + total) % total )) ;;
            j|J)  CURSOR=$(( (CURSOR + 1) % total )) ;;
            a|A)  set_all 1 ;;
            n|N)  set_all 0 ;;
            q|Q)  printf '\033[?25h'; echo "Aborted — nothing installed."; exit 0 ;;
            '')   printf '\033[?25h'; return 0 ;;         # Enter -> confirm
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

Pick the install target (native Ubuntu or WSL) and which phases and programs
to install. With no options and an interactive terminal, you are prompted for
the target and shown a selection menu. Stow symlinks are always applied.

Options:
  -a, --all      Install everything without prompting (required when there is
                 no interactive terminal, e.g. piped input or CI). Respects the
                 target: desktop/hardware-only programs are skipped on WSL.
      --native   Force the install target to native Ubuntu (skip the prompt).
      --wsl      Force the install target to WSL (skip the prompt).
  -h, --help     Show this help and exit.

If neither --native nor --wsl is given, the target is auto-detected.
EOF
}

# --- Main (only runs when executed directly, not sourced) ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    RUN_ALL=0
    ENV_OVERRIDE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--all|-y|--yes) RUN_ALL=1 ;;
            --native) ENV_OVERRIDE="native" ;;
            --wsl)    ENV_OVERRIDE="wsl" ;;
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

    # Resolve the install target before building the plan (it drives defaults).
    detected="$(detect_environment)"
    if [ -n "$ENV_OVERRIDE" ]; then
        ENVIRONMENT="$ENV_OVERRIDE"
        echo "Install target: $ENVIRONMENT"
    elif [ "$RUN_ALL" -eq 1 ]; then
        ENVIRONMENT="$detected"
        echo "Install target (auto-detected): $ENVIRONMENT"
    elif [ -t 0 ]; then
        choose_environment "$detected"
    else
        echo "No interactive terminal detected. Re-run with --all (optionally --wsl/--native)." >&2
        exit 2
    fi
    # Propagate the target to program scripts (e.g. neovim.sh picks tarball vs snap).
    export ENVIRONMENT

    build_plan
    # --all accepts the target-aware defaults; interactively, refine via the menu.
    if [ "$RUN_ALL" -ne 1 ] && [ -t 0 ]; then
        select_menu
    fi

    apply_stow
    run_plan

    print_summary
fi
