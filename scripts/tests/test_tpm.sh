#!/bin/bash
# Tests for scripts/programs/tpm.sh
#
# Runnable on its own:  bash scripts/tests/test_tpm.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- tpm.sh: skip when TPM dir exists ---
echo ""
echo "=== tpm.sh: skip when already installed ==="
MOCK_HOME="$TEST_DIR/home_tpm"
mkdir -p "$MOCK_HOME/.tmux/plugins/tpm"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/tpm.sh" 2>&1)
code=$?
assert_exit_zero "tpm.sh exits 0 when already installed" "$code"
assert_output_contains "tpm.sh prints 'Already installed'" "Already installed" "$output"

# --- tpm.sh: invokes install_plugins when binary is present ---
echo ""
echo "=== tpm.sh: invokes install_plugins ==="
MOCK_HOME="$TEST_DIR/home_tpm_install"
TPM_BIN="$MOCK_HOME/.tmux/plugins/tpm/bin"
mkdir -p "$TPM_BIN"
SENTINEL="$TEST_DIR/install_plugins_called"
cat > "$TPM_BIN/install_plugins" <<EOF
#!/bin/bash
touch "$SENTINEL"
EOF
chmod +x "$TPM_BIN/install_plugins"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/tpm.sh" 2>&1)
code=$?
assert_exit_zero "tpm.sh exits 0 when install_plugins present" "$code"
assert_file_exists "tpm.sh invokes install_plugins" "$SENTINEL"
assert_output_contains "tpm.sh announces plugin install" "Installing tmux plugins" "$output"



finish_suite "tpm.sh"
