#!/bin/bash
# Tests for scripts/programs/openrgb.sh
#
# Runnable on its own:  bash scripts/tests/test_openrgb.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- openrgb.sh: skip when already installed ---
echo ""
echo "=== openrgb.sh: skip when already installed ==="
mock_sudo
MOCK_HOME="$TEST_DIR/home_orgb_skip"
mkdir -p "$MOCK_HOME/etc/modules-load.d" "$MOCK_HOME/etc/systemd/system"
touch "$MOCK_HOME/etc/modules-load.d/openrgb.conf"
touch "$MOCK_HOME/etc/systemd/system/openrgb-off.service"
output=$(PATH="$BIN_DIR:$PATH" \
    OPENRGB_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    OPENRGB_SYSTEMD_DIR="$MOCK_HOME/etc/systemd/system" \
    OPENRGB_FORCE_PKG_INSTALLED=1 \
    bash "$DOTFILES_DIR/scripts/programs/openrgb.sh" 2>&1)
code=$?
assert_exit_zero "openrgb.sh exits 0 when already installed" "$code"
assert_output_contains "openrgb.sh prints 'Already installed: openrgb'" "Already installed: openrgb" "$output"
rm -f "$BIN_DIR/sudo"

# --- openrgb.sh: installs pkgs, loads modules, sets LEDs off, installs service ---
echo ""
echo "=== openrgb.sh: installs, persists modules, enables service ==="
ORGB_LOG="$TEST_DIR/orgb_calls.log"
: > "$ORGB_LOG"
mock_sudo
for cmd in apt-get modprobe openrgb systemctl; do
    cat > "$BIN_DIR/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$ORGB_LOG"
exit 0
EOF
    chmod +x "$BIN_DIR/$cmd"
done
cat > "$BIN_DIR/tee" <<EOF
#!/bin/bash
echo "tee \$*" >> "$ORGB_LOG"
/bin/cat > "\$1"
exit 0
EOF
chmod +x "$BIN_DIR/tee"
MOCK_HOME="$TEST_DIR/home_orgb_install"
mkdir -p "$MOCK_HOME/etc/modules-load.d" "$MOCK_HOME/etc/systemd/system"
output=$(PATH="$BIN_DIR:$PATH" \
    OPENRGB_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    OPENRGB_SYSTEMD_DIR="$MOCK_HOME/etc/systemd/system" \
    OPENRGB_FORCE_PKG_INSTALLED=0 \
    bash "$DOTFILES_DIR/scripts/programs/openrgb.sh" 2>&1) || true
log_content="$(cat "$ORGB_LOG" 2>/dev/null)"
assert_output_contains "openrgb.sh apt-installs openrgb" "openrgb" "$log_content"
assert_output_contains "openrgb.sh apt-installs i2c-tools" "i2c-tools" "$log_content"
assert_output_contains "openrgb.sh modprobes i2c-dev" "modprobe i2c-dev" "$log_content"
assert_output_contains "openrgb.sh sets LEDs off (static black)" "openrgb --mode static --color 000000" "$log_content"
assert_output_contains "openrgb.sh enables openrgb-off service" "systemctl enable --now openrgb-off.service" "$log_content"
assert_file_exists "openrgb.sh writes /etc/modules-load.d/openrgb.conf" "$MOCK_HOME/etc/modules-load.d/openrgb.conf"
assert_file_exists "openrgb.sh writes openrgb-off.service" "$MOCK_HOME/etc/systemd/system/openrgb-off.service"
assert_output_contains "openrgb.sh prints BIOS firmware-LED pointer" "list-devices" "$output"
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/modprobe" "$BIN_DIR/openrgb" "$BIN_DIR/systemctl" "$BIN_DIR/tee" "$BIN_DIR/sudo"

finish_suite "openrgb.sh"
