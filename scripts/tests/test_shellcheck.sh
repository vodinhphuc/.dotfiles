#!/bin/bash
# Tests for scripts/programs/shellcheck.sh
#
# Runnable on its own:  bash scripts/tests/test_shellcheck.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- shellcheck.sh: skip when shellcheck already in PATH ---
echo ""
echo "=== shellcheck.sh: skip when already installed ==="
mock_cmd shellcheck
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/shellcheck.sh" 2>&1)
code=$?
assert_exit_zero "shellcheck.sh exits 0 when already installed" "$code"
assert_output_contains "shellcheck.sh prints 'Already installed: shellcheck'" "Already installed: shellcheck" "$output"
rm -f "$BIN_DIR/shellcheck"

finish_suite "shellcheck.sh"
