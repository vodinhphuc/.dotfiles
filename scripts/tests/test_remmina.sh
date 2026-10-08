#!/bin/bash
# Tests for scripts/programs/remmina.sh
#
# Runnable on its own:  bash scripts/tests/test_remmina.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

SOURCES="$TEST_DIR/sources.list.d"
mkdir -p "$SOURCES"

# --- remmina.sh: skip when every package is installed ---
echo ""
echo "=== remmina.sh: skip when already installed ==="
REMMINA_LOG="$TEST_DIR/remmina_calls.log"
: > "$REMMINA_LOG"
mock_sudo
mock_dpkg_query_all_installed
mock_logging_cmds "$REMMINA_LOG" apt-get
output=$(PATH="$BIN_DIR:$PATH" REMMINA_SOURCES_DIR="$SOURCES" \
    bash "$DOTFILES_DIR/scripts/programs/remmina.sh" 2>&1)
code=$?
assert_exit_zero "remmina.sh exits 0 when already installed" "$code"
assert_output_contains "remmina.sh prints 'Already installed: remmina'" "Already installed: remmina" "$output"
assert_output_contains "remmina.sh prints 'Already installed: remmina-plugin-rdp'" "Already installed: remmina-plugin-rdp" "$output"
assert_equals "remmina.sh does not call apt-get when nothing is missing" "" "$(cat "$REMMINA_LOG")"
assert_output_not_contains "remmina.sh prints no PPA warning without the PPA" "remmina-next" "$output"

# --- remmina.sh: installs only the missing packages ---
echo ""
echo "=== remmina.sh: installs only missing packages ==="
: > "$REMMINA_LOG"
# Only the vnc plugin is missing.
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
[ "${*: -1}" = "remmina-plugin-vnc" ] && exit 1
echo "install ok installed"
EOF
chmod +x "$BIN_DIR/dpkg-query"
output=$(PATH="$BIN_DIR:$PATH" REMMINA_SOURCES_DIR="$SOURCES" \
    bash "$DOTFILES_DIR/scripts/programs/remmina.sh" 2>&1)
code=$?
assert_exit_zero "remmina.sh exits 0 after installing" "$code"
assert_equals "remmina.sh installs exactly the missing package" \
    "apt-get install -y remmina-plugin-vnc" "$(cat "$REMMINA_LOG")"
assert_output_contains "remmina.sh still reports installed packages" "Already installed: remmina-plugin-secret" "$output"

# --- remmina.sh: warns about a stale remmina-next PPA ---
echo ""
echo "=== remmina.sh: warns about remmina-next PPA ==="
mock_dpkg_query_all_installed
touch "$SOURCES/remmina-ppa-team-ubuntu-remmina-next-resolute.sources"
output=$(PATH="$BIN_DIR:$PATH" REMMINA_SOURCES_DIR="$SOURCES" \
    bash "$DOTFILES_DIR/scripts/programs/remmina.sh" 2>&1)
code=$?
assert_exit_zero "remmina.sh exits 0 when the PPA is present (warn only)" "$code"
assert_output_contains "remmina.sh warns about the remmina-next PPA" "warning: remmina-next PPA source found" "$output"
assert_output_contains "remmina.sh prints the PPA removal command" "add-apt-repository --remove ppa:remmina-ppa-team/remmina-next" "$output"
assert_file_exists "remmina.sh leaves the PPA source file in place" \
    "$SOURCES/remmina-ppa-team-ubuntu-remmina-next-resolute.sources"

finish_suite "remmina.sh"
