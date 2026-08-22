#!/bin/bash
# Tests for scripts/programs/docker.sh
#
# Runnable on its own:  bash scripts/tests/test_docker.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- docker.sh: skip when docker already in PATH ---
echo ""
echo "=== docker.sh: skip when already installed ==="
mock_cmd docker
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/docker.sh" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when already installed" "$code"
assert_output_contains "docker.sh prints 'Already installed'" "Already installed" "$output"

finish_suite "docker.sh"
