#!/bin/bash
# Tests for scripts/programs/custome_zsh.sh
#
# Runnable on its own:  bash scripts/tests/test_custome_zsh.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- custome_zsh.sh: skips all components when already present ---
echo ""
echo "=== custome_zsh.sh: skip all components when already installed ==="
MOCK_HOME="$TEST_DIR/home_zsh"
mkdir -p "$MOCK_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
mkdir -p "$MOCK_HOME/.oh-my-zsh/custom/plugins/conda-zsh-completion"
touch "$MOCK_HOME/.antigen.zsh"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/custome_zsh.sh" 2>&1)
code=$?
assert_exit_zero "custome_zsh.sh exits 0 when all components installed" "$code"
assert_output_contains "custome_zsh.sh prints 'Already installed' for oh-my-zsh" "Already installed: oh-my-zsh" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for antigen" "Already installed: ~/.antigen.zsh" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for powerlevel10k" "Already installed: powerlevel10k" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for conda-zsh-completion" "Already installed: conda-zsh-completion" "$output"

finish_suite "custome_zsh.sh"
