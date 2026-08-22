#!/bin/bash
# Tests for scripts/programs/fan_control.sh
#
# Runnable on its own:  bash scripts/tests/test_fan_control.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- fan_control.sh: skip when already installed ---
echo ""
echo "=== fan_control.sh: skip when already installed ==="
mock_sudo
# dpkg-query mock that reports both packages installed
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
# Args we care about: -W -f=${Status} <pkg>
exit 0
EOF
chmod +x "$BIN_DIR/dpkg-query"
MOCK_HOME="$TEST_DIR/home_fan_skip"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
touch "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
output=$(PATH="$BIN_DIR:$PATH" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=1 \
    bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1)
code=$?
assert_exit_zero "fan_control.sh exits 0 when already installed" "$code"
assert_output_contains "fan_control.sh prints 'Already installed: fan_control'" "Already installed: fan_control" "$output"
rm -f "$BIN_DIR/dpkg-query" "$BIN_DIR/sudo"

# --- fan_control.sh: installs packages, loads module, writes modules-load.d ---
echo ""
echo "=== fan_control.sh: installs packages and persists module ==="
FAN_LOG="$TEST_DIR/fan_calls.log"
: > "$FAN_LOG"
mock_sudo
cat > "$BIN_DIR/apt-get" <<EOF
#!/bin/bash
echo "apt-get \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/apt-get"
cat > "$BIN_DIR/modprobe" <<EOF
#!/bin/bash
echo "modprobe \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/modprobe"
# Mock tee to write file and log call
cat > "$BIN_DIR/tee" <<EOF
#!/bin/bash
echo "tee \$*" >> "$FAN_LOG"
/bin/cat > "\$1"
exit 0
EOF
chmod +x "$BIN_DIR/tee"
# Mock cat to read stdin and output (for the heredoc in fan_control.sh)
cat > "$BIN_DIR/cat" <<EOF
#!/bin/bash
/bin/cat "\$@"
exit 0
EOF
chmod +x "$BIN_DIR/cat"
MOCK_HOME="$TEST_DIR/home_fan_install"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
output=$(PATH="$BIN_DIR" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=0 \
    /bin/bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1) || true
log_content="$(cat "$FAN_LOG" 2>/dev/null)"
assert_output_contains "fan_control.sh apt-installs lm-sensors" "lm-sensors" "$log_content"
assert_output_contains "fan_control.sh apt-installs fancontrol" "fancontrol" "$log_content"
assert_output_contains "fan_control.sh modprobes nct6775" "modprobe nct6775" "$log_content"
assert_file_exists "fan_control.sh writes /etc/modules-load.d/nct6775.conf" "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
assert_output_contains "fan_control.sh prints next-steps pointer" "docs/guides/fans.md" "$output"
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/modprobe" "$BIN_DIR/tee" "$BIN_DIR/cat" "$BIN_DIR/sudo"

# --- fan_control.sh: skip via real dpkg-query branch ---
echo ""
echo "=== fan_control.sh: skip when dpkg-query reports installed ==="
mock_sudo
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
echo "install ok installed"
exit 0
EOF
chmod +x "$BIN_DIR/dpkg-query"
MOCK_HOME="$TEST_DIR/home_fan_dpkg"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
touch "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
output=$(PATH="$BIN_DIR:$PATH" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1)
code=$?
assert_exit_zero "fan_control.sh exits 0 when dpkg-query reports installed" "$code"
assert_output_contains "fan_control.sh skips via real dpkg-query path" "Already installed: fan_control" "$output"
rm -f "$BIN_DIR/dpkg-query" "$BIN_DIR/sudo"

finish_suite "fan_control.sh"
