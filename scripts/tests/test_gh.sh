#!/bin/bash
# Tests for scripts/programs/gh.sh
#
# Runnable on its own:  bash scripts/tests/test_gh.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- gh.sh: skip when gh already in PATH ---
echo ""
echo "=== gh.sh: skip when already installed ==="
mock_cmd gh
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/gh.sh" 2>&1)
code=$?
assert_exit_zero "gh.sh exits 0 when already installed" "$code"
assert_output_contains "gh.sh prints 'Already installed: gh'" "Already installed: gh" "$output"
rm -f "$BIN_DIR/gh"

finish_suite "gh.sh"
