#!/bin/bash
# Tests for run_step orchestrator function in install.sh
# Usage: bash scripts/test_orchestrator.sh

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# --- Test helpers ---

assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: '$expected'"
        echo "        actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" content="$3"
    if grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' in $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local desc="$1" file="$2" content="$3"
    if ! grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' NOT in $file"
        FAIL=$((FAIL + 1))
    fi
}

# --- Setup: override state file paths and source functions ---

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export STATE_FILE="$TEST_DIR/.install_state"
export ERRORS_FILE="$TEST_DIR/.install_errors"
export LOG_FILE="$TEST_DIR/.install.log"
touch "$ERRORS_FILE"

# Source only the functions (not main body) from install.sh
# Then disable set -e so test assertions can handle failures gracefully
source "$DOTFILES_DIR/scripts/install.sh"
set +e

# --- Tests ---

echo ""
echo "=== Test: successful step is recorded in state file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_file_contains "state file contains test_ok" "$STATE_FILE" "test_ok"
assert_file_not_contains "errors file does not contain test_ok" "$ERRORS_FILE" "test_ok"
assert_equals "STEPS_OK has test_ok" "test_ok" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: already-completed step is skipped ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_equals "STEPS_SKIP has test_ok" "test_ok" "${STEPS_SKIP[0]:-}"
assert_equals "STEPS_OK is empty" "" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: failing step is recorded in errors file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_fail" <(echo "exit 1")
assert_file_contains "errors file contains test_fail" "$ERRORS_FILE" "test_fail"
assert_file_not_contains "state file does not contain test_fail" "$STATE_FILE" "test_fail"
assert_equals "STEPS_FAIL has test_fail" "test_fail" "${STEPS_FAIL[0]:-}"

echo ""
echo "=== Test: failure in one step does not abort subsequent steps ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_abort_check" <(echo "exit 0")
assert_file_contains "state file contains test_abort_check after prior failure" "$STATE_FILE" "test_abort_check"

echo ""
echo "=== Test: exit inside script does not kill orchestrator ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_exit_trap" <(printf '#!/bin/bash\nexit 42')
assert_equals "orchestrator still running after exit 42" "test_exit_trap" "${STEPS_FAIL[0]:-}"

echo ""
echo "=== Test: disable_cdrom_source comments .list and disables .sources ==="
# Mock sudo to passthrough so the function can edit temp files without root
sudo() { "$@"; }
APT_SOURCES_LIST="$TEST_DIR/sources.list"
APT_SOURCES_DIR="$TEST_DIR/sources.list.d"
mkdir -p "$APT_SOURCES_DIR"
printf 'deb cdrom:[Ubuntu]/ questing main\ndeb http://archive.ubuntu.com/ubuntu questing main\n' > "$APT_SOURCES_LIST"
printf 'deb [signed-by=/x] file:/cdrom questing main\n' > "$APT_SOURCES_DIR/cdrom.list"
printf 'Types: deb\nURIs: file:/cdrom\nSuites: questing\n' > "$APT_SOURCES_DIR/cdrom.sources"
printf 'Types: deb\nURIs: http://archive.ubuntu.com/ubuntu\nSuites: questing\n' > "$APT_SOURCES_DIR/ubuntu.sources"
disable_cdrom_source >/dev/null

assert_equals "cdrom line in sources.list commented" "#deb cdrom:[Ubuntu]/ questing main" "$(sed -n '1p' "$APT_SOURCES_LIST")"
assert_equals "non-cdrom line in sources.list untouched" "deb http://archive.ubuntu.com/ubuntu questing main" "$(sed -n '2p' "$APT_SOURCES_LIST")"
assert_equals "cdrom .list commented" "#deb [signed-by=/x] file:/cdrom questing main" "$(cat "$APT_SOURCES_DIR/cdrom.list")"
[ ! -f "$APT_SOURCES_DIR/cdrom.sources" ] && [ -f "$APT_SOURCES_DIR/cdrom.sources.disabled" ]
assert_equals "cdrom .sources renamed to .disabled" "0" "$?"
[ -f "$APT_SOURCES_DIR/ubuntu.sources" ]
assert_equals "non-cdrom .sources left in place" "0" "$?"
unset -f sudo

echo ""
echo "=== Test: build_plan discovers program scripts + phases ==="
PROGRAMS_DIR="$TEST_DIR/programs"
mkdir -p "$PROGRAMS_DIR"
: > "$PROGRAMS_DIR/alpha.sh"
: > "$PROGRAMS_DIR/beta.sh"
build_plan
assert_equals "first item is system_update phase" "system_update" "${ITEM_KEYS[0]}"
assert_equals "second item is base phase" "base" "${ITEM_KEYS[1]}"
assert_equals "program scripts discovered (2 phases + 2 progs)" "4" "${#ITEM_KEYS[@]}"
assert_equals "alpha program present" "alpha" "${ITEM_KEYS[2]}"
assert_equals "everything starts selected" "1" "${ITEM_ON[3]}"

echo ""
echo "=== Test: toggle / set_all / is_selected ==="
toggle_item 4    # turn off beta (index 3)
assert_equals "toggle_item turns beta off" "0" "${ITEM_ON[3]}"
toggle_item 4    # back on
assert_equals "toggle_item turns beta back on" "1" "${ITEM_ON[3]}"
toggle_item 99   # out of range -> no-op, no crash
assert_equals "out-of-range toggle is a no-op" "1" "${ITEM_ON[3]}"
set_all 0
is_selected system_update; assert_equals "set_all 0 deselects system_update" "1" "$?"
set_all 1
is_selected system_update; assert_equals "set_all 1 selects system_update" "0" "$?"

echo ""
echo "=== Test: install target (native vs wsl) defaults ==="
# Use the real program scripts so native-only classification applies
PROGRAMS_DIR="$DOTFILES_DIR/scripts/programs"

is_native_only fan_control; assert_equals "fan_control is native-only" "0" "$?"
is_native_only glow;        assert_equals "glow is not native-only" "1" "$?"

ENVIRONMENT="native"; build_plan
is_selected fan_control; assert_equals "native: fan_control selected by default" "0" "$?"
is_selected glow;        assert_equals "native: glow selected by default" "0" "$?"

ENVIRONMENT="wsl"; build_plan
is_selected fan_control; assert_equals "wsl: fan_control deselected by default" "1" "$?"
is_selected terminator;  assert_equals "wsl: terminator deselected by default" "1" "$?"
is_selected glow;        assert_equals "wsl: glow still selected by default" "0" "$?"
is_selected custome_zsh; assert_equals "wsl: custome_zsh still selected by default" "0" "$?"

echo ""
echo "=== Test: detect_environment honors WSL_DISTRO_NAME ==="
assert_equals "WSL_DISTRO_NAME set -> wsl" "wsl" "$(WSL_DISTRO_NAME=Ubuntu detect_environment)"

# --- Summary ---
echo ""
echo "=========================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
