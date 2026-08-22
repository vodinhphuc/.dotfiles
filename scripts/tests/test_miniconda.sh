#!/bin/bash
# Tests for scripts/programs/miniconda.sh
#
# Runnable on its own:  bash scripts/tests/test_miniconda.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- miniconda.sh: skip when miniconda3 dir exists ---
echo ""
echo "=== miniconda.sh: skip when already installed ==="
MOCK_HOME="$TEST_DIR/home_conda"
mkdir -p "$MOCK_HOME/miniconda3"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/miniconda.sh" 2>&1)
code=$?
assert_exit_zero "miniconda.sh exits 0 when already installed" "$code"
assert_output_contains "miniconda.sh prints 'Already installed'" "Already installed" "$output"

finish_suite "miniconda.sh"
