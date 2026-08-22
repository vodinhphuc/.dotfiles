#!/bin/bash
# Tests for scripts/programs/visual_code.sh
#
# Runnable on its own:  bash scripts/tests/test_visual_code.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- visual_code.sh: skip when code already in PATH ---
echo ""
echo "=== visual_code.sh: skip when already installed ==="
mock_cmd code
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/visual_code.sh" 2>&1)
code=$?
assert_exit_zero "visual_code.sh exits 0 when already installed" "$code"
assert_output_contains "visual_code.sh prints 'Already installed'" "Already installed" "$output"

finish_suite "visual_code.sh"
