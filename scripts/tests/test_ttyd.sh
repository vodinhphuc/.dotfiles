#!/bin/bash
# Tests for scripts/programs/ttyd.sh
#
# Runnable on its own:  bash scripts/tests/test_ttyd.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- ttyd.sh: skip when already installed ---
echo ""
echo "=== ttyd.sh: skip when already installed ==="
mock_sudo
MOCK_HOME="$TEST_DIR/home_ttyd_skip"
mkdir -p "$MOCK_HOME/systemd_user" "$MOCK_HOME/config_ttyd"
touch "$MOCK_HOME/systemd_user/ttyd.service"
touch "$MOCK_HOME/config_ttyd/credentials"
output=$(PATH="$BIN_DIR:$PATH" \
    TTYD_SYSTEMD_USER_DIR="$MOCK_HOME/systemd_user" \
    TTYD_CONFIG_DIR="$MOCK_HOME/config_ttyd" \
    TTYD_FORCE_PKG_INSTALLED=1 \
    TTYD_SKIP_SYSTEMCTL=1 \
    bash "$DOTFILES_DIR/scripts/programs/ttyd.sh" 2>&1)
code=$?
assert_exit_zero "ttyd.sh exits 0 when already installed" "$code"
assert_output_contains "ttyd.sh prints 'Already installed: ttyd'" "Already installed: ttyd" "$output"
rm -f "$BIN_DIR/sudo"

# --- ttyd.sh: generates credentials and writes a user service ---
echo ""
echo "=== ttyd.sh: generates credentials and installs service ==="
mock_sudo
MOCK_HOME="$TEST_DIR/home_ttyd_install"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR:$PATH" \
    TTYD_SYSTEMD_USER_DIR="$MOCK_HOME/systemd_user" \
    TTYD_CONFIG_DIR="$MOCK_HOME/config_ttyd" \
    TTYD_FORCE_PKG_INSTALLED=1 \
    TTYD_SKIP_SYSTEMCTL=1 \
    bash "$DOTFILES_DIR/scripts/programs/ttyd.sh" 2>&1)
code=$?
assert_exit_zero "ttyd.sh exits 0 on first configure" "$code"
assert_file_exists "ttyd.sh writes the user service" "$MOCK_HOME/systemd_user/ttyd.service"
assert_file_exists "ttyd.sh writes a credentials file" "$MOCK_HOME/config_ttyd/credentials"

# A world-readable password would defeat the point of generating one.
cred_mode=$(stat -c '%a' "$MOCK_HOME/config_ttyd/credentials" 2>/dev/null)
assert_equals "ttyd.sh chmods credentials to 600" "600" "$cred_mode"

# -W is what makes the terminal writable; without it ttyd 1.7+ is read-only and
# the browser silently cannot type, which is the whole point of installing it.
assert_file_contains "ttyd service passes -W (writable)" "$MOCK_HOME/systemd_user/ttyd.service" -- "-W"
# Binding to 0.0.0.0 would expose a full shell to the LAN.
assert_file_contains "ttyd service binds an interface, not all addresses" "$MOCK_HOME/systemd_user/ttyd.service" "-i tailscale0"
assert_output_not_contains "ttyd.sh never binds 0.0.0.0" "0.0.0.0" "$output"
assert_file_contains "ttyd service attaches the tmux session" "$MOCK_HOME/systemd_user/ttyd.service" "tmux new -A -s dotfile"
rm -f "$BIN_DIR/sudo"

finish_suite "ttyd.sh"
