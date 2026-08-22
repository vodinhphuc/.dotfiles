#!/bin/bash
# Tests for scripts/programs/wezterm.sh
#
# Runnable on its own:  bash scripts/tests/test_wezterm.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- wezterm.sh: skip every step when wezterm is already provisioned ---
echo ""
echo "=== wezterm.sh: skip when already installed ==="
mock_cmd wezterm
mock_cmd update-alternatives
mock_cmd gsettings
mock_sudo
MOCK_HOME="$TEST_DIR/home_wezterm_skip"
mkdir -p "$MOCK_HOME/.config/wezterm/bg"
# wezterm mocked into PATH means the key/repo/install block is skipped whole --
# which is also what keeps this test off the network. WEZTERM_ALT_LINK must
# point somewhere that is NOT wezterm, or this assertion silently inverts on a
# machine where wezterm is genuinely the default already.
mkdir -p "$TEST_DIR/alt_other"
ln -sf /usr/bin/terminator "$TEST_DIR/alt_other/x-terminal-emulator"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" \
    WEZTERM_ALT_LINK="$TEST_DIR/alt_other/x-terminal-emulator" \
    bash "$DOTFILES_DIR/scripts/programs/wezterm.sh" 2>&1)
code=$?
assert_exit_zero "wezterm.sh exits 0 when already installed" "$code"
assert_output_contains "wezterm.sh prints 'Already installed: wezterm'" "Already installed: wezterm" "$output"
assert_output_contains "wezterm.sh skips the bg folder when present" "Already installed: WezTerm background folder" "$output"
assert_output_not_contains "wezterm.sh does not reinstall the package" "Installing WezTerm..." "$output"
assert_output_contains "wezterm.sh claims the x-terminal-emulator default" "Setting WezTerm as the default x-terminal-emulator" "$output"
assert_output_contains "wezterm.sh sets the GNOME default terminal" "Setting WezTerm as the GNOME default terminal" "$output"

# --- wezterm.sh: leaves the default alone once it already points at wezterm ---
echo ""
echo "=== wezterm.sh: default-terminal step is idempotent ==="
mkdir -p "$TEST_DIR/alt"
ln -sf /usr/bin/wezterm "$TEST_DIR/alt/x-terminal-emulator"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" WEZTERM_ALT_LINK="$TEST_DIR/alt/x-terminal-emulator" \
    bash "$DOTFILES_DIR/scripts/programs/wezterm.sh" 2>&1)
code=$?
assert_exit_zero "wezterm.sh exits 0 when already the default" "$code"
assert_output_contains "wezterm.sh skips re-setting the alternative" "Already installed: WezTerm as default x-terminal-emulator" "$output"
assert_output_not_contains "wezterm.sh does not re-run update-alternatives" "Setting WezTerm as the default x-terminal-emulator" "$output"

# --- wezterm.sh: creates the background folder when it is missing ---
echo ""
echo "=== wezterm.sh: creates background folder when absent ==="
MOCK_HOME="$TEST_DIR/home_wezterm_bg"
mkdir -p "$MOCK_HOME"   # no .config/wezterm/bg -- the script must create it
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/wezterm.sh" 2>&1)
code=$?
assert_exit_zero "wezterm.sh exits 0 when creating bg folder" "$code"
assert_dir_exists "wezterm.sh creates the bg folder" "$MOCK_HOME/.config/wezterm/bg"
rm -f "$BIN_DIR/wezterm"

finish_suite "wezterm.sh"
