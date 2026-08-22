#!/bin/bash
# Tests for scripts/programs/terminator.sh
#
# Runnable on its own:  bash scripts/tests/test_terminator.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- terminator.sh: should NOT say "Already installed" when terminator is absent ---
echo ""
echo "=== terminator.sh: does NOT say 'Already installed' when terminator is absent ==="
MOCK_HOME="$TEST_DIR/home_term_absent"
mkdir -p "$MOCK_HOME"
mock_sudo
mock_cmd apt-get
# Run with empty PATH (no terminator) + mocked sudo + mocked apt-get
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/terminator.sh" 2>&1) || true
assert_output_not_contains "terminator.sh does not say 'Already installed' when absent" "Already installed" "$output"

# --- terminator.sh: writes config when terminator is present ---
echo ""
echo "=== terminator.sh: writes config when terminator is installed ==="
mock_cmd terminator
mock_cmd update-alternatives
mock_cmd gsettings
MOCK_HOME="$TEST_DIR/home_term_present"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/terminator.sh" 2>&1)
code=$?
assert_exit_zero "terminator.sh exits 0 when terminator already installed" "$code"
assert_file_exists "terminator config is written" "$MOCK_HOME/.config/terminator/config"

# --- terminator.sh: must NOT clobber an existing config ---
# Regression guard: this script used to `cat >` the config unconditionally,
# wiping whatever Terminator's own preferences GUI had written (background
# image, font) on every install.sh run.
echo ""
echo "=== terminator.sh: preserves an existing config ==="
MOCK_HOME="$TEST_DIR/home_term_existing"
mkdir -p "$MOCK_HOME/.config/terminator"
printf '[profiles]\n[[default]]\n  background_image = /my/wallpaper.jpg\n' \
    > "$MOCK_HOME/.config/terminator/config"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/terminator.sh" 2>&1)
code=$?
assert_exit_zero "terminator.sh exits 0 with an existing config" "$code"
assert_output_contains "terminator.sh says it left the config alone" "Already installed: Terminator config" "$output"
assert_file_contains "terminator.sh preserves the user's background_image" \
    "$MOCK_HOME/.config/terminator/config" "background_image = /my/wallpaper.jpg"
assert_output_not_contains "terminator.sh does not rewrite the config" "Terminator config written" "$output"

finish_suite "terminator.sh"
