#!/bin/bash
# Tests for scripts/programs/glow.sh
#
# Runnable on its own:  bash scripts/tests/test_glow.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- glow.sh: skip when glow already in PATH ---
echo ""
echo "=== glow.sh: skip when glow already installed ==="
mock_cmd glow
mock_cmd batcat   # also bypass the bat install path so this test isolates glow
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/glow.sh" 2>&1)
code=$?
assert_exit_zero "glow.sh exits 0 when glow already installed" "$code"
assert_output_contains "glow.sh prints 'Already installed: glow'" "Already installed: glow" "$output"
assert_output_contains "glow.sh prints 'Already installed: bat'" "Already installed: bat" "$output"
rm -f "$BIN_DIR/glow" "$BIN_DIR/batcat"

# --- glow.sh: skip when batcat already in PATH ---
echo ""
echo "=== glow.sh: skip when bat already installed ==="
mock_cmd batcat
mock_cmd glow
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/glow.sh" 2>&1)
code=$?
assert_exit_zero "glow.sh exits 0 when bat already installed" "$code"
assert_output_contains "glow.sh (bat-block) prints 'Already installed: glow'" "Already installed: glow" "$output"
assert_output_contains "glow.sh prints 'Already installed: bat'" "Already installed: bat" "$output"
rm -f "$BIN_DIR/glow" "$BIN_DIR/batcat"

finish_suite "glow.sh"
