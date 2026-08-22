#!/bin/bash
# Tests for scripts/programs/uv.sh
#
# Runnable on its own:  bash scripts/tests/test_uv.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- uv.sh: skip when uv already in PATH, still (re)generates completions ---
echo ""
echo "=== uv.sh: skip when already installed ==="
mock_cmd uv
mock_cmd uvx
MOCK_HOME="$TEST_DIR/home_uv"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/uv.sh" 2>&1)
code=$?
assert_exit_zero "uv.sh exits 0 when already installed" "$code"
assert_output_contains "uv.sh prints 'Already installed: uv'" "Already installed: uv" "$output"
assert_file_exists "uv.sh generates uv.zsh completion" "$MOCK_HOME/.config/uv/uv.zsh"
assert_file_exists "uv.sh generates uvx.zsh completion" "$MOCK_HOME/.config/uv/uvx.zsh"
rm -f "$BIN_DIR/uv" "$BIN_DIR/uvx"

finish_suite "uv.sh"
